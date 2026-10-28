// FineTuneTests/ChannelDSPTests.swift
// Compressor, limiter and spatial processing — driven offline through the RT process() entry point.

import Testing
import Foundation
@testable import FineTune

private let sr = 48_000.0

/// Interleaved stereo square wave (constant |x| so detector levels are exact).
private func square(amplitude: Float, frames: Int, period: Int = 48, rightScale: Float = 1) -> [Float] {
    var out = [Float](repeating: 0, count: frames * 2)
    for i in 0..<frames {
        let v: Float = ((i / (period / 2)) % 2 == 0) ? amplitude : -amplitude
        out[i * 2] = v
        out[i * 2 + 1] = v * rightScale
    }
    return out
}

private func run(_ processor: ChannelDSPProcessor, _ input: [Float], block: Int = 512) -> [Float] {
    var data = input
    let frames = data.count / 2
    var offset = 0
    data.withUnsafeMutableBufferPointer { ptr in
        while offset < frames {
            let n = min(block, frames - offset)
            processor.process(ptr.baseAddress! + offset * 2, frameCount: n)
            offset += n
        }
    }
    return data
}

private func peak(_ x: [Float], from: Int = 0) -> Float {
    x[from...].reduce(0) { max($0, abs($1)) }
}

private func db(_ linear: Float) -> Float { 20 * log10(max(linear, 1e-9)) }

@Suite("ChannelDSPSettings — model")
struct ChannelDSPSettingsTests {

    @Test("Defaults are inactive")
    func defaults() {
        #expect(ChannelDSPSettings().isInactive)
        #expect(ChannelDSPSettings.off.isInactive)
    }

    @Test("Spatial with default values is neutral even when enabled")
    func neutralSpatial() {
        var s = SpatialSettings(); s.isEnabled = true
        #expect(s.isNeutral)
        s.width = 1.2
        #expect(!s.isNeutral)
    }

    @Test("Decoding clamps out-of-range and missing values")
    func decodeClamps() throws {
        let json = #"{"dynamics":{"compressorEnabled":true,"ratio":999,"thresholdDB":-500},"spatial":{"width":9}}"#
        let s = try JSONDecoder().decode(ChannelDSPSettings.self, from: Data(json.utf8))
        #expect(s.dynamics.ratio == DynamicsSettings.ratioRange.upperBound)
        #expect(s.dynamics.thresholdDB == DynamicsSettings.thresholdRange.lowerBound)
        #expect(s.spatial.width == SpatialSettings.widthRange.upperBound)
        #expect(s.dynamics.attackMs == 10)
    }

    @Test("Round-trips through JSON")
    func roundTrip() throws {
        var s = ChannelDSPSettings()
        s.dynamics = DynamicsPreset.gameNight.settings
        s.spatial = SpatialPreset.arena.settings
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(ChannelDSPSettings.self, from: data) == s)
    }

    @Test("Every preset stays inside valid ranges")
    func presetsValid() {
        for p in DynamicsPreset.allCases { #expect(p.settings == p.settings.clamped) }
        for p in SpatialPreset.allCases { #expect(p.settings == p.settings.clamped) }
    }
}

@Suite("ChannelDSPProcessor — compressor")
struct CompressorTests {

    private func compressor(threshold: Double, ratio: Double, knee: Double = 0, makeup: Double = 0) -> ChannelDSPProcessor {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings()
        s.dynamics.compressorEnabled = true
        s.dynamics.thresholdDB = threshold; s.dynamics.ratio = ratio
        s.dynamics.kneeDB = knee; s.dynamics.makeupDB = makeup
        s.dynamics.attackMs = 1; s.dynamics.releaseMs = 50
        p.updateSettings(s)
        return p
    }

    @Test("Steady signal above threshold is reduced by the ratio")
    func ratioMath() {
        // 0.5 ≈ -6.02 dBFS, threshold -20, ratio 4 → reduction = 13.98 × 0.75 ≈ 10.5 dB.
        let out = run(compressor(threshold: -20, ratio: 4), square(amplitude: 0.5, frames: 48_000))
        let level = db(peak(out, from: 40_000))
        #expect(abs(level - (-6.02 - 10.49)) < 0.5, "got \(level) dB")
    }

    @Test("Signal below threshold is untouched")
    func belowThreshold() {
        let input = square(amplitude: 0.05, frames: 24_000)   // ≈ -26 dBFS
        let out = run(compressor(threshold: -20, ratio: 4), input)
        #expect(abs(db(peak(out, from: 20_000)) - db(0.05)) < 0.1)
    }

    @Test("Makeup gain lifts the output")
    func makeup() {
        let base = run(compressor(threshold: -20, ratio: 4), square(amplitude: 0.5, frames: 48_000))
        let lifted = run(compressor(threshold: -20, ratio: 4, makeup: 6), square(amplitude: 0.5, frames: 48_000))
        #expect(abs((db(peak(lifted, from: 40_000)) - db(peak(base, from: 40_000))) - 6) < 0.3)
    }

    @Test("Ratio 1:1 is transparent")
    func unity() {
        let out = run(compressor(threshold: -40, ratio: 1), square(amplitude: 0.5, frames: 24_000))
        #expect(abs(db(peak(out, from: 20_000)) - db(0.5)) < 0.05)
    }

    @Test("Gain reduction meter reports the squash")
    func meter() {
        let p = compressor(threshold: -20, ratio: 4)
        _ = run(p, square(amplitude: 0.5, frames: 48_000))
        #expect(p.gainReductionDB > 8)
    }

    @Test("Soft knee reduces less than a hard knee at the threshold")
    func knee() {
        let hard = run(compressor(threshold: -6, ratio: 8, knee: 0), square(amplitude: 0.5, frames: 24_000))
        let soft = run(compressor(threshold: -6, ratio: 8, knee: 12), square(amplitude: 0.5, frames: 24_000))
        #expect(peak(soft, from: 20_000) <= peak(hard, from: 20_000) + 0.2)
        #expect(peak(soft, from: 20_000) > 0.1)
    }
}

@Suite("ChannelDSPProcessor — limiter")
struct LimiterTests {

    private func limiter(ceiling: Double) -> ChannelDSPProcessor {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings()
        s.dynamics.limiterEnabled = true; s.dynamics.ceilingDB = ceiling; s.dynamics.limiterReleaseMs = 50
        p.updateSettings(s)
        return p
    }

    @Test("Steady loud signal is held at the ceiling")
    func steady() {
        let out = run(limiter(ceiling: -6), square(amplitude: 1.0, frames: 48_000))
        #expect(peak(out, from: 10_000) <= 0.5012)
        #expect(peak(out, from: 10_000) > 0.45)
    }

    @Test("A sudden transient after silence never exceeds the ceiling")
    func transient() {
        var input = [Float](repeating: 0, count: 6000 * 2)
        input += square(amplitude: 1.0, frames: 3000)
        input += [Float](repeating: 0, count: 3000 * 2)
        let out = run(limiter(ceiling: -6), input)
        #expect(peak(out) <= 0.5012, "peak \(peak(out))")
    }

    @Test("Quiet material is not changed apart from the look-ahead delay")
    func quiet() {
        let input = square(amplitude: 0.1, frames: 24_000)
        let out = run(limiter(ceiling: -1), input)
        #expect(abs(peak(out, from: 10_000) - 0.1) < 0.001)
    }

    @Test("Limiter output is finite for non-finite input")
    func nanSafe() {
        var input = square(amplitude: 0.5, frames: 4000)
        input[100] = .nan; input[201] = .infinity
        let out = run(limiter(ceiling: -3), input)
        #expect(out.allSatisfy { $0.isFinite })
    }
}

@Suite("ChannelDSPProcessor — spatial")
struct SpatialTests {

    private func spatial(_ configure: (inout SpatialSettings) -> Void) -> ChannelDSPProcessor {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings()
        s.spatial.isEnabled = true
        configure(&s.spatial)
        p.updateSettings(s)
        return p
    }

    @Test("A neutral chain is disabled and leaves audio bit-exact")
    func neutral() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        p.updateSettings(ChannelDSPSettings())
        #expect(!p.isEnabled)
        let input = square(amplitude: 0.7, frames: 1000)
        #expect(run(p, input) == input)
    }

    @Test("Width 0 collapses stereo to mono")
    func mono() {
        let p = spatial { $0.width = 0 }
        let out = run(p, square(amplitude: 0.6, frames: 2000, rightScale: -1))   // pure side signal
        #expect(peak(out) < 1e-6)
    }

    @Test("Width 2 doubles the side component")
    func wide() {
        let p = spatial { $0.width = 2 }
        let out = run(p, square(amplitude: 0.4, frames: 2000, rightScale: -1))   // L = -R
        #expect(abs(peak(out) - 0.8) < 0.001)
    }

    @Test("Crossfeed leaks the left channel into the right")
    func crossfeed() {
        let p = spatial { $0.crossfeed = 0.6 }
        var input = square(amplitude: 0.5, frames: 8000)
        for i in 0..<8000 { input[i * 2 + 1] = 0 }                  // left only
        let out = run(p, input)
        var rightPeak: Float = 0
        for i in 4000..<8000 { rightPeak = max(rightPeak, abs(out[i * 2 + 1])) }
        #expect(rightPeak > 0.01)
    }

    @Test("Room adds energy after the dry signal ends")
    func room() {
        let p = spatial { $0.room = 1 }
        var input = square(amplitude: 0.5, frames: 400)
        input += [Float](repeating: 0, count: 2000 * 2)
        let out = run(p, input)
        var tail: Float = 0
        for i in 450..<1200 { tail = max(tail, abs(out[i * 2])) }
        #expect(tail > 0.01)
    }

    @Test("Maximum settings stay bounded and finite")
    func bounded() {
        let p = spatial { $0.width = 2; $0.crossfeed = 1; $0.room = 1 }
        let out = run(p, square(amplitude: 0.9, frames: 48_000, rightScale: -0.5))
        #expect(out.allSatisfy { $0.isFinite })
        #expect(peak(out) < 4)
    }

    @Test("Changing the sample rate keeps processing valid")
    func sampleRateChange() {
        let p = spatial { $0.crossfeed = 0.5; $0.room = 0.5 }
        p.updateSampleRate(96_000)
        let out = run(p, square(amplitude: 0.5, frames: 20_000))
        #expect(out.allSatisfy { $0.isFinite })
    }
}

@Suite("ChannelDSPProcessor — state after re-enabling")
struct ProcessorReenableTests {

    @Test("A compressor switched back on does not reuse its old envelope")
    func compressorFresh() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var on = ChannelDSPSettings()
        on.dynamics.compressorEnabled = true; on.dynamics.thresholdDB = -30; on.dynamics.ratio = 10
        on.dynamics.attackMs = 1; on.dynamics.releaseMs = 2000       // slow release keeps the envelope deep
        p.updateSettings(on)
        _ = run(p, square(amplitude: 0.9, frames: 20_000))           // drive deep into reduction
        p.updateSettings(ChannelDSPSettings())                        // everything off
        _ = run(p, square(amplitude: 0.1, frames: 100))
        p.updateSettings(on)
        let out = run(p, square(amplitude: 0.01, frames: 200))        // quiet: well below threshold
        // With fresh state a signal under the threshold passes at unity from the first sample.
        #expect(abs(peak(out) - 0.01) < 0.0005, "got \(peak(out))")
    }

    @Test("A limiter switched back on starts at unity gain")
    func limiterFresh() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var on = ChannelDSPSettings()
        on.dynamics.limiterEnabled = true; on.dynamics.ceilingDB = -12; on.dynamics.limiterReleaseMs = 500
        p.updateSettings(on)
        _ = run(p, square(amplitude: 1, frames: 10_000))              // gain pulled far down
        p.updateSettings(ChannelDSPSettings())
        _ = run(p, square(amplitude: 0.1, frames: 100))
        p.updateSettings(on)
        let out = run(p, square(amplitude: 0.1, frames: 1000))
        #expect(abs(peak(out, from: 100) - 0.1) < 0.002, "got \(peak(out, from: 100))")
    }
}
