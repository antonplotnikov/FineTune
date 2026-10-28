// FineTune/Audio/Dynamics/BinauralConvolver.swift
import Foundation
import Accelerate

/// Binaural "virtual speakers": convolves a stereo signal with measured head-related impulse
/// responses so that headphones sound like two loudspeakers placed at ±`speakerAngle` in front of
/// the listener (the left channel plays from the left speaker, the right from the right one, and
/// each ear also hears the far speaker delayed and filtered by the head — the cues that make
/// sound appear outside the head).
///
/// Uses the MIT KEMAR measurements (`KEMARHRTF`). Head symmetry means one ipsilateral and one
/// contralateral filter describe both speakers:
///
///     outL = L ⊛ ipsi + R ⊛ contra
///     outR = R ⊛ ipsi + L ⊛ contra
///
/// **RT-safety:** everything is allocated in `init`. `process` runs `vDSP_conv` on preallocated
/// scratch buffers. The main thread prepares new filters in an idle bank and flips `activeBank`
/// (three banks, so a bank being read is never the one being written); on a change the audio thread
/// cross-fades old→new across one chunk so moving the angle doesn't click.
nonisolated final class BinauralConvolver: @unchecked Sendable {

    static let maxTaps = 1024
    static let chunkFrames = 4096
    private static let bankCount = 3
    private static let historyLength = maxTaps - 1

    // MARK: Filter banks (main writes an idle bank, audio thread reads the active one)

    private let ipsiBanks: UnsafeMutablePointer<Float>
    private let contraBanks: UnsafeMutablePointer<Float>
    private let bankTaps: UnsafeMutablePointer<Int>
    private nonisolated(unsafe) var activeBank = 0
    private var nextBank = 1   // main thread only

    // MARK: Audio-thread state

    private let sigL: UnsafeMutablePointer<Float>   // [history | current chunk]
    private let sigR: UnsafeMutablePointer<Float>
    private let earL: UnsafeMutablePointer<Float>
    private let earR: UnsafeMutablePointer<Float>
    private let altL: UnsafeMutablePointer<Float>
    private let altR: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private nonisolated(unsafe) var lastBank = 0

    // MARK: Info (main thread)

    private(set) var azimuth = 30
    private(set) var configuredRate: Double = 0
    private var hasConfigured = false

    // MARK: - Lifecycle

    init() {
        let m = Self.maxTaps, b = Self.bankCount, c = Self.chunkFrames, h = Self.historyLength
        ipsiBanks = .allocate(capacity: m * b); ipsiBanks.initialize(repeating: 0, count: m * b)
        contraBanks = .allocate(capacity: m * b); contraBanks.initialize(repeating: 0, count: m * b)
        bankTaps = .allocate(capacity: b); bankTaps.initialize(repeating: 1, count: b)
        sigL = .allocate(capacity: h + c); sigL.initialize(repeating: 0, count: h + c)
        sigR = .allocate(capacity: h + c); sigR.initialize(repeating: 0, count: h + c)
        earL = .allocate(capacity: c); earL.initialize(repeating: 0, count: c)
        earR = .allocate(capacity: c); earR.initialize(repeating: 0, count: c)
        altL = .allocate(capacity: c); altL.initialize(repeating: 0, count: c)
        altR = .allocate(capacity: c); altR.initialize(repeating: 0, count: c)
        scratch = .allocate(capacity: c); scratch.initialize(repeating: 0, count: c)
        // Bank 0 = identity (taps = 1, ipsi = 1, contra = 0): harmless until configured.
        ipsiBanks[0] = 1
    }

    deinit {
        ipsiBanks.deallocate(); contraBanks.deallocate(); bankTaps.deallocate()
        sigL.deallocate(); sigR.deallocate(); earL.deallocate(); earR.deallocate()
        altL.deallocate(); altR.deallocate(); scratch.deallocate()
    }

    // MARK: - Configuration (main thread)

    /// Loads the HRIR pair for the nearest measured angle, resampled to `sampleRate`.
    func configure(speakerAngle: Double, sampleRate: Double) {
        let az = KEMARHRTF.nearestAzimuth(to: speakerAngle)
        let (rawIpsi, rawContra) = KEMARHRTF.hrir(azimuth: az)
        guard !rawIpsi.isEmpty else { return }

        // Drop the shared leading silence (the speaker's travel time) but keep the interaural delay.
        let onset = Self.onsetIndex(of: rawIpsi)
        var ipsi = Array(rawIpsi.dropFirst(onset))
        var contra = Array(rawContra.dropFirst(onset))

        ipsi = Self.resample(ipsi, from: KEMARHRTF.sampleRate, to: sampleRate)
        contra = Self.resample(contra, from: KEMARHRTF.sampleRate, to: sampleRate)
        let taps = min(Self.maxTaps, max(ipsi.count, contra.count))
        ipsi = Array((ipsi + [Float](repeating: 0, count: max(0, taps - ipsi.count))).prefix(taps))
        contra = Array((contra + [Float](repeating: 0, count: max(0, taps - contra.count))).prefix(taps))

        // Level: unit power gain for uncorrelated left/right input, so switching it on isn't louder.
        let energy = ipsi.reduce(0) { $0 + $1 * $1 } + contra.reduce(0) { $0 + $1 * $1 }
        let gain = energy > 1e-12 ? 1 / energy.squareRoot() : 1

        let bank = nextBank
        let base = bank * Self.maxTaps
        for i in 0..<Self.maxTaps {
            ipsiBanks[base + i] = i < taps ? ipsi[i] * gain : 0
            contraBanks[base + i] = i < taps ? contra[i] * gain : 0
        }
        bankTaps[bank] = taps
        azimuth = az
        configuredRate = sampleRate
        // The very first configuration has nothing meaningful to fade from.
        if !hasConfigured { lastBank = bank; hasConfigured = true }
        activeBank = bank                       // publish
        nextBank = (bank + 1) % Self.bankCount
    }

    /// Filters currently in use (for tests and diagnostics).
    func currentFilters() -> (ipsi: [Float], contra: [Float]) {
        let bank = activeBank, taps = bankTaps[bank], base = bank * Self.maxTaps
        return ((0..<taps).map { ipsiBanks[base + $0] }, (0..<taps).map { contraBanks[base + $0] })
    }

    // MARK: - Audio thread

    /// Clears the convolution history (call when the effect is switched on).
    func resetHistory() {
        let total = Self.historyLength + Self.chunkFrames
        for i in 0..<total { sigL[i] = 0; sigR[i] = 0 }
        lastBank = activeBank
    }

    /// Processes interleaved stereo in place. `mix` blends dry (0) → binaural (1).
    func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int, mix: Float) {
        let h = Self.historyLength
        var done = 0
        while done < frameCount {
            let n = min(Self.chunkFrames, frameCount - done)
            let io = buffer + done * 2

            for j in 0..<n {
                let l = io[j * 2], r = io[j * 2 + 1]
                sigL[h + j] = l.isFinite ? l : 0
                sigR[h + j] = r.isFinite ? r : 0
            }

            let bank = activeBank
            convolve(bank: bank, frames: n, outL: earL, outR: earR)
            if bank != lastBank {
                // Filters changed: blend the previous filters out over this chunk.
                convolve(bank: lastBank, frames: n, outL: altL, outR: altR)
                let step = 1 / Float(n)
                for j in 0..<n {
                    let w = Float(j + 1) * step
                    earL[j] = altL[j] * (1 - w) + earL[j] * w
                    earR[j] = altR[j] * (1 - w) + earR[j] * w
                }
                lastBank = bank
            }

            let dryAmount = 1 - mix
            for j in 0..<n {
                io[j * 2] = sigL[h + j] * dryAmount + earL[j] * mix
                io[j * 2 + 1] = sigR[h + j] * dryAmount + earR[j] * mix
            }

            // Keep the newest `h` samples as history for the next chunk.
            memmove(sigL, sigL + n, h * MemoryLayout<Float>.size)
            memmove(sigR, sigR + n, h * MemoryLayout<Float>.size)
            done += n
        }
    }

    /// outL = L⊛ipsi + R⊛contra, outR = R⊛ipsi + L⊛contra.
    private func convolve(bank: Int, frames: Int, outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>) {
        let taps = bankTaps[bank]
        let base = bank * Self.maxTaps
        let ipsiEnd = ipsiBanks + base + (taps - 1)       // reversed access = true convolution
        let contraEnd = contraBanks + base + (taps - 1)
        let start = Self.historyLength - (taps - 1)       // so each output sees `taps - 1` past samples
        let len = vDSP_Length(frames), n = vDSP_Length(taps)

        vDSP_conv(sigL + start, 1, ipsiEnd, -1, outL, 1, len, n)
        vDSP_conv(sigR + start, 1, contraEnd, -1, scratch, 1, len, n)
        vDSP_vadd(outL, 1, scratch, 1, outL, 1, len)

        vDSP_conv(sigR + start, 1, ipsiEnd, -1, outR, 1, len, n)
        vDSP_conv(sigL + start, 1, contraEnd, -1, scratch, 1, len, n)
        vDSP_vadd(outR, 1, scratch, 1, outR, 1, len)
    }

    // MARK: - Helpers (pure; used at configure time and by tests)

    /// Index of the first tap that reaches 5% of the peak, minus a small lead-in so the onset isn't clipped.
    static func onsetIndex(of h: [Float]) -> Int {
        let peak = h.reduce(0) { max($0, abs($1)) }
        guard peak > 0, let first = h.firstIndex(where: { abs($0) >= 0.05 * peak }) else { return 0 }
        return max(0, first - 3)
    }

    /// Windowed-sinc (Lanczos) resampling of an impulse response. Amplitude is scaled by the rate
    /// ratio so the filter's DC gain is unchanged.
    static func resample(_ x: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !x.isEmpty, abs(sourceRate - targetRate) > 1 else { return x }
        let ratio = targetRate / sourceRate
        let cutoff = min(1.0, ratio)                 // low-pass when downsampling
        let lobes = 16.0
        let outCount = Int((Double(x.count) * ratio).rounded(.up))
        var out = [Float](repeating: 0, count: outCount)
        for m in 0..<outCount {
            let t = Double(m) / ratio
            let lo = Int((t - lobes / cutoff).rounded(.down)), hi = Int((t + lobes / cutoff).rounded(.up))
            var sum = 0.0
            for i in max(0, lo)...min(x.count - 1, max(hi, 0)) {
                let d = t - Double(i)
                let arg = d * cutoff
                let sinc = abs(arg) < 1e-9 ? 1.0 : sin(Double.pi * arg) / (Double.pi * arg)
                let wArg = d * cutoff / lobes
                let window = abs(wArg) >= 1 ? 0 : (abs(wArg) < 1e-9 ? 1.0 : sin(Double.pi * wArg) / (Double.pi * wArg))
                sum += Double(x[i]) * sinc * window * cutoff
            }
            out[m] = Float(sum / ratio)
        }
        return out
    }
}
