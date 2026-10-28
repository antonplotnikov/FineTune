// FineTune/Audio/EQ/SpectrumAnalyzer.swift
import Foundation
import Accelerate

/// Lock-free single-producer ring buffer the audio thread writes post-processing samples into.
///
/// RT-safety: the buffer is allocated once in `init`; `capture` only reads/writes preallocated
/// memory and one Int index, with no locks, allocation, or Objective-C/Swift runtime calls.
/// The reader (main thread) tolerates torn reads — a slightly stale window only blurs one frame.
nonisolated final class SpectrumTap: @unchecked Sendable {
    static let capacity = 8192  // power of two

    let buffer: UnsafeMutablePointer<Float>
    /// Total samples written; the newest sample is at `(writeIndex - 1) & mask`.
    nonisolated(unsafe) var writeIndex: Int = 0
    /// Audio thread skips all work unless the UI has asked for a spectrum.
    nonisolated(unsafe) var isCapturing = false
    nonisolated(unsafe) var sampleRate: Double = 48_000

    init() {
        buffer = .allocate(capacity: Self.capacity)
        buffer.initialize(repeating: 0, count: Self.capacity)
    }

    deinit { buffer.deallocate() }

    /// Copies the first channel of an interleaved buffer into the ring. RT-safe.
    @inline(__always)
    func capture(samples: UnsafePointer<Float>, frameCount: Int, channels: Int) {
        guard isCapturing, channels > 0 else { return }
        let mask = Self.capacity - 1
        var index = writeIndex
        for frame in 0..<frameCount {
            buffer[index & mask] = samples[frame * channels]
            index &+= 1
        }
        writeIndex = index
    }
}

/// Turns the newest samples of a `SpectrumTap` into smoothed, log-spaced dBFS magnitudes.
/// Main-thread only (owns FFT scratch buffers and smoothing state).
@MainActor
final class SpectrumAnalyzer {
    static let fftSize = 4096
    static let pointCount = 128
    nonisolated static let floorDB: Float = -90

    private let tap: SpectrumTap
    private let log2n = vDSP_Length(log2(Double(SpectrumAnalyzer.fftSize)))
    private nonisolated(unsafe) let fftSetup: FFTSetup
    private var window = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
    private var real = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
    private var imag = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize / 2)
    private var frame = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
    private var smoothed = [Float](repeating: SpectrumAnalyzer.floorDB, count: SpectrumAnalyzer.pointCount)

    init(tap: SpectrumTap) {
        self.tap = tap
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Clears smoothing so a re-opened analyzer doesn't show stale peaks.
    func reset() {
        smoothed = [Float](repeating: Self.floorDB, count: Self.pointCount)
    }

    /// Latest spectrum: `pointCount` dBFS values at log-spaced frequencies 20 Hz…20 kHz.
    func snapshot() -> [Float] {
        let n = Self.fftSize
        let mask = SpectrumTap.capacity - 1
        let end = tap.writeIndex
        for i in 0..<n { frame[i] = tap.buffer[(end - n + i) & mask] }

        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(n))

        var db = [Float](repeating: Self.floorDB, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in
                    fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // zrip output is scaled by 2; normalize so a full-scale sine reads ≈ 0 dBFS.
                let scale = 1.0 / Float(n)
                for k in 0..<(n / 2) {
                    let mag = sqrt(rp[k] * rp[k] + ip[k] * ip[k]) * scale
                    db[k] = max(Self.floorDB, 20 * log10(max(mag, 1e-9)))
                }
            }
        }

        // Re-bin to log-spaced points: take the loudest FFT bin within each point's span.
        let binHz = Float(tap.sampleRate) / Float(n)
        let lo = log10(Float(ParametricBand.minFrequency)), hi = log10(Float(ParametricBand.maxFrequency))
        let nyquist = Float(tap.sampleRate) / 2
        for p in 0..<Self.pointCount {
            let f0 = pow(10, lo + (hi - lo) * Float(p) / Float(Self.pointCount))
            let f1 = pow(10, lo + (hi - lo) * Float(p + 1) / Float(Self.pointCount))
            var value = Self.floorDB
            if f0 < nyquist {
                let b0 = max(1, Int(f0 / binHz)), b1 = min(n / 2 - 1, max(b0, Int(f1 / binHz)))
                for b in b0...b1 { value = max(value, db[b]) }
            }
            // Instant attack, gentle release.
            smoothed[p] = value > smoothed[p] ? value : smoothed[p] + (value - smoothed[p]) * 0.25
        }
        return smoothed
    }
}
