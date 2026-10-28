// FineTune/Audio/Dynamics/ChannelDSPProcessor.swift
import Foundation

/// Per-app stereo DSP chain: spatial imaging → compressor → look-ahead limiter.
///
/// **RT-safety:** every buffer is allocated once in `init`. `process` performs only arithmetic on
/// preallocated memory — no allocation, locks, logging, or Swift runtime calls. Parameters are
/// plain Floats published from the main thread (aligned 32-bit stores are atomic on all supported
/// CPUs); a momentarily mixed parameter set is inaudible and harmless.
///
/// Like `EQProcessor`, each tap (primary / crossfade secondary) owns its own instance because the
/// delay lines and envelopes are mutable state that concurrent callbacks must not share.
nonisolated final class ChannelDSPProcessor: @unchecked Sendable {

    // MARK: - Capacities

    private static let delayCapacity = 8192          // power of two; ≥ 21 ms at 192 kHz
    private static let lookaheadCapacity = 128       // power of two; ≥ max look-ahead samples + 1

    // MARK: - Published parameters (main thread writes, audio thread reads)

    private nonisolated(unsafe) var active = false

    private nonisolated(unsafe) var spatialOn = false
    private nonisolated(unsafe) var widthAmount: Float = 1
    private nonisolated(unsafe) var crossAmount: Float = 0
    private nonisolated(unsafe) var roomAmount: Float = 0
    private nonisolated(unsafe) var levelCompensation: Float = 1
    private nonisolated(unsafe) var binauralOn = false
    private nonisolated(unsafe) var binauralMix: Float = 1
    private let binaural = BinauralConvolver()
    private nonisolated(unsafe) var configuredAzimuth = -1
    private nonisolated(unsafe) var configuredRate: Double = -1

    private nonisolated(unsafe) var compOn = false
    private nonisolated(unsafe) var thresholdDB: Float = -18
    private nonisolated(unsafe) var slope: Float = 1 - 1 / 3   // 1 - 1/ratio
    private nonisolated(unsafe) var kneeDB: Float = 6
    private nonisolated(unsafe) var makeupDB: Float = 0
    private nonisolated(unsafe) var attackCoeff: Float = 0.99
    private nonisolated(unsafe) var releaseCoeff: Float = 0.999

    private nonisolated(unsafe) var limOn = false
    private nonisolated(unsafe) var ceilingLinear: Float = 0.891
    private nonisolated(unsafe) var limReleaseCoeff: Float = 0.999

    private nonisolated(unsafe) var sampleRate: Double
    private nonisolated(unsafe) var crossDelay = 13
    private nonisolated(unsafe) var roomTap1 = 336
    private nonisolated(unsafe) var roomTap2 = 624
    private nonisolated(unsafe) var roomTap3 = 1008
    private nonisolated(unsafe) var crossLPCoeff: Float = 0.08
    private nonisolated(unsafe) var lookahead = 34

    // MARK: - Audio-thread state

    private let delayL: UnsafeMutablePointer<Float>
    private let delayR: UnsafeMutablePointer<Float>
    private nonisolated(unsafe) var delayWrite = 0
    private nonisolated(unsafe) var lpL: Float = 0
    private nonisolated(unsafe) var lpR: Float = 0

    private nonisolated(unsafe) var compEnv: Float = 0          // smoothed gain reduction (dB, ≤ 0)

    private let limAudioL: UnsafeMutablePointer<Float>
    private let limAudioR: UnsafeMutablePointer<Float>
    private let limTargets: UnsafeMutablePointer<Float>
    private let limHeld: UnsafeMutablePointer<Float>
    private nonisolated(unsafe) var limWrite = 0
    private nonisolated(unsafe) var limGain: Float = 1
    /// Running state for O(1) window-min and boxcar average.
    private nonisolated(unsafe) var limWinMin: Float = 1
    private nonisolated(unsafe) var limWinAge = 0
    private nonisolated(unsafe) var limHeldSum: Double = 0
    /// Set by the main thread whenever a stage is switched on (or the look-ahead length changes).
    /// The audio thread clears all stale state before its next buffer, so nothing that was
    /// processed before a stage was off can leak into audio after it is turned back on.
    private nonisolated(unsafe) var stateResetRequested = false

    /// Largest gain reduction (positive dB) seen in the last buffer, for UI metering.
    private(set) nonisolated(unsafe) var gainReductionDB: Float = 0

    var isEnabled: Bool { active }

    // MARK: - Init

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let dc = Self.delayCapacity, lc = Self.lookaheadCapacity
        delayL = .allocate(capacity: dc); delayL.initialize(repeating: 0, count: dc)
        delayR = .allocate(capacity: dc); delayR.initialize(repeating: 0, count: dc)
        limAudioL = .allocate(capacity: lc); limAudioL.initialize(repeating: 0, count: lc)
        limAudioR = .allocate(capacity: lc); limAudioR.initialize(repeating: 0, count: lc)
        limTargets = .allocate(capacity: lc); limTargets.initialize(repeating: 1, count: lc)
        limHeld = .allocate(capacity: lc); limHeld.initialize(repeating: 1, count: lc)
        recomputeRateDependents()
    }

    deinit {
        delayL.deallocate(); delayR.deallocate()
        limAudioL.deallocate(); limAudioR.deallocate()
        limTargets.deallocate(); limHeld.deallocate()
    }

    // MARK: - Main-thread API

    private nonisolated(unsafe) var lastSettings = ChannelDSPSettings()

    var currentSettings: ChannelDSPSettings { lastSettings }

    func updateSettings(_ settings: ChannelDSPSettings) {
        lastSettings = settings
        let d = settings.dynamics.clamped
        let s = settings.spatial.clamped

        // A stage that is being switched on must not inherit state from before it was off.
        let nowSpatial = !s.isNeutral
        if (d.compressorEnabled && !compOn) || (d.limiterEnabled && !limOn)
            || (nowSpatial && !spatialOn) || (s.isEnabled && s.binaural && s.binauralMix > 0 && !binauralOn) {
            stateResetRequested = true
        }

        // Spatial
        widthAmount = Float(s.width)
        crossAmount = Float(s.crossfeed)
        roomAmount = Float(s.room)
        // Binaural replaces crossfeed (the HRTF already contains the head-shadowed far-ear path).
        let wantsBinaural = s.isEnabled && s.binaural && s.binauralMix > 0
        levelCompensation = 1 / (1 + (wantsBinaural ? 0 : crossAmount * 0.6) + roomAmount * 0.35)
        spatialOn = !s.isNeutral
        let azimuth = KEMARHRTF.nearestAzimuth(to: s.speakerAngle)
        if wantsBinaural, azimuth != configuredAzimuth || sampleRate != configuredRate {
            // Prepared off the audio thread; the convolver swaps banks atomically.
            binaural.configure(speakerAngle: s.speakerAngle, sampleRate: sampleRate)
            configuredAzimuth = azimuth
            configuredRate = sampleRate
        }
        binauralMix = Float(s.binauralMix)
        binauralOn = wantsBinaural

        // Compressor
        thresholdDB = Float(d.thresholdDB)
        slope = Float(1 - 1 / d.ratio)
        kneeDB = Float(d.kneeDB)
        makeupDB = Float(d.makeupDB)
        attackCoeff = Self.timeCoefficient(ms: d.attackMs, sampleRate: sampleRate)
        releaseCoeff = Self.timeCoefficient(ms: d.releaseMs, sampleRate: sampleRate)

        // Limiter
        ceilingLinear = Float(pow(10.0, d.ceilingDB / 20.0))
        limReleaseCoeff = Self.timeCoefficient(ms: d.limiterReleaseMs, sampleRate: sampleRate)

        compOn = d.compressorEnabled
        limOn = d.limiterEnabled
        active = compOn || limOn || spatialOn
    }

    func updateSampleRate(_ newRate: Double) {
        guard newRate > 0, newRate != sampleRate else { return }
        sampleRate = newRate
        recomputeRateDependents()
        updateSettings(lastSettings)
    }

    private func recomputeRateDependents() {
        let sr = sampleRate
        crossDelay = max(1, Int(0.00027 * sr))
        roomTap1 = min(Self.delayCapacity - 1, Int(0.007 * sr))
        roomTap2 = min(Self.delayCapacity - 1, Int(0.013 * sr))
        roomTap3 = min(Self.delayCapacity - 1, Int(0.021 * sr))
        crossLPCoeff = Float(1 - exp(-2 * Double.pi * 700 / sr))
        lookahead = min(Self.lookaheadCapacity - 2, max(2, Int(0.0007 * sr)))
        stateResetRequested = true
    }

    private static func timeCoefficient(ms: Double, sampleRate: Double) -> Float {
        Float(exp(-1.0 / (max(ms, 0.01) * 0.001 * sampleRate)))
    }

    // MARK: - Audio thread

    /// Processes interleaved stereo in place.
    func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard active else { return }

        if stateResetRequested { stateResetRequested = false; resetAllState() }

        // Binaural runs block-wise ahead of the per-sample chain: width first, then the HRTF convolution.
        let doBinaural = spatialOn && binauralOn
        if doBinaural {
            let width = widthAmount
            if width != 1 {
                for frame in 0..<frameCount {
                    let l = buffer[frame * 2], r = buffer[frame * 2 + 1]
                    let mid = (l + r) * 0.5
                    let side = (l - r) * 0.5 * width
                    buffer[frame * 2] = mid + side
                    buffer[frame * 2 + 1] = mid - side
                }
            }
            binaural.process(buffer, frameCount: frameCount, mix: binauralMix)
        }

        let dMask = Self.delayCapacity - 1
        let lMask = Self.lookaheadCapacity - 1
        let doSpatial = spatialOn, doComp = compOn, doLim = limOn
        let width = widthAmount, cross = crossAmount, room = roomAmount, comp = levelCompensation
        let lp = crossLPCoeff
        let look = lookahead
        var worstReduction: Float = 0

        for frame in 0..<frameCount {
            var l = buffer[frame * 2]
            var r = buffer[frame * 2 + 1]
            if !l.isFinite { l = 0 }
            if !r.isFinite { r = 0 }

            // ---- Spatial ----
            if doSpatial {
                if width != 1 && !doBinaural {
                    let mid = (l + r) * 0.5
                    let side = (l - r) * 0.5 * width
                    l = mid + side
                    r = mid - side
                }
                let w = delayWrite
                delayL[w & dMask] = l
                delayR[w & dMask] = r
                var outL = l, outR = r

                if cross > 0 && !doBinaural {
                    // Head-shadow: delayed, low-passed opposite channel.
                    let xl = delayR[(w - crossDelay) & dMask]
                    let xr = delayL[(w - crossDelay) & dMask]
                    lpL += lp * (xl - lpL)
                    lpR += lp * (xr - lpR)
                    outL += cross * lpL
                    outR += cross * lpR
                }
                if room > 0 {
                    let roomL = 0.5 * delayL[(w - roomTap1) & dMask]
                        + 0.35 * delayR[(w - roomTap2) & dMask]
                        + 0.25 * delayL[(w - roomTap3) & dMask]
                    let roomR = 0.5 * delayR[(w - roomTap1) & dMask]
                        + 0.35 * delayL[(w - roomTap2) & dMask]
                        + 0.25 * delayR[(w - roomTap3) & dMask]
                    outL += room * 0.3 * roomL
                    outR += room * 0.3 * roomR
                }
                delayWrite = w &+ 1
                l = outL * comp
                r = outR * comp
            }

            // ---- Compressor (stereo-linked, soft knee) ----
            if doComp {
                let peak = max(abs(l), abs(r))
                let inDB = 6.0206 * log2f(max(peak, 1e-5))
                let over = inDB - thresholdDB
                var reduction: Float
                if 2 * over < -kneeDB {
                    reduction = 0
                } else if 2 * abs(over) <= kneeDB {
                    let t = over + kneeDB * 0.5
                    reduction = -slope * t * t / (2 * max(kneeDB, 1e-3))
                } else {
                    reduction = -slope * over
                }
                // Attack when reduction deepens, release when it relaxes.
                let coeff = reduction < compEnv ? attackCoeff : releaseCoeff
                compEnv = coeff * compEnv + (1 - coeff) * reduction
                let gain = exp2f((compEnv + makeupDB) * 0.16609640)
                l *= gain
                r *= gain
                worstReduction = max(worstReduction, -compEnv)
            }

            // ---- Look-ahead limiter ----
            if doLim {
                let w = limWrite
                limAudioL[w & lMask] = l
                limAudioR[w & lMask] = r
                let peak = max(abs(l), abs(r))
                let target: Float = peak > ceilingLinear ? ceilingLinear / peak : 1
                limTargets[w & lMask] = target

                // Sliding minimum over the look-ahead span (so the delayed sample is always covered).
                // A new low replaces the minimum outright; only when the old minimum ages out of
                // the window do we rescan, which happens at most once per `look` samples.
                if target <= limWinMin {
                    limWinMin = target
                    limWinAge = 0
                } else {
                    limWinAge += 1
                    if limWinAge > look {
                        var best: Float = 1
                        var bestAge = 0
                        for k in 0...look {
                            let t = limTargets[(w - k) & lMask]
                            if t < best { best = t; bestAge = k }
                        }
                        limWinMin = best
                        limWinAge = bestAge
                    }
                }
                let windowMin = limWinMin
                // Instant attack on the window minimum, exponential release back toward unity.
                limGain = windowMin < limGain ? windowMin : limGain + (1 - limGain) * (1 - limReleaseCoeff)
                let held = min(limGain, windowMin)
                // Boxcar smoothing of the held gain via a running sum; every term ≤ the target
                // of the delayed sample. The sample leaving the window is the one `look` back.
                limHeldSum += Double(held) - Double(limHeld[(w - look) & lMask])
                limHeld[w & lMask] = held
                let smoothed = Float(limHeldSum / Double(look))

                l = limAudioL[(w - look) & lMask] * smoothed
                r = limAudioR[(w - look) & lMask] * smoothed
                limWrite = w &+ 1
                if smoothed < 1 { worstReduction = max(worstReduction, -6.0206 * log2f(max(smoothed, 1e-4))) }
            }

            buffer[frame * 2] = l
            buffer[frame * 2 + 1] = r
        }

        gainReductionDB = worstReduction
    }

    /// Clears every stage's history. Audio thread only; allocation-free.
    private func resetAllState() {
        compEnv = 0
        lpL = 0; lpR = 0
        for i in 0..<Self.delayCapacity { delayL[i] = 0; delayR[i] = 0 }
        resetLimiter()
        binaural.resetHistory()
    }

    private func resetLimiter() {
        let lc = Self.lookaheadCapacity
        for i in 0..<lc {
            limAudioL[i] = 0; limAudioR[i] = 0; limTargets[i] = 1; limHeld[i] = 1
        }
        limGain = 1
        limWinMin = 1
        limWinAge = 0
        limHeldSum = Double(lookahead)
    }
}
