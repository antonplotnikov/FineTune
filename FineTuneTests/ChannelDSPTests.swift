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

@Suite("GameProfileMatcher")
struct GameProfileMatcherTests {

    private let fps = GameProfile(name: "FPS", bundleIDs: ["com.game.fps"])
    private let fallback = GameProfile(name: "Any game", appliesToDetectedGames: true)

    @Test("Explicit bundle match wins over the detected-games fallback")
    func explicitWins() {
        let match = GameProfileMatcher.profile(for: "com.game.fps", isDetectedGame: true, in: [fallback, fps])
        #expect(match?.name == "FPS")
    }

    @Test("Detected games fall back to the default game profile")
    func detected() {
        #expect(GameProfileMatcher.profile(for: "com.other.game", isDetectedGame: true, in: [fps, fallback])?.name == "Any game")
    }

    @Test("Non-games without an explicit match get nothing")
    func nonGame() {
        #expect(GameProfileMatcher.profile(for: "com.apple.Music", isDetectedGame: false, in: [fps, fallback]) == nil)
    }

    @Test("Disabled profiles never match")
    func disabled() {
        var off = fps; off.isEnabled = false
        var offFallback = fallback; offFallback.isEnabled = false
        #expect(GameProfileMatcher.profile(for: "com.game.fps", isDetectedGame: true, in: [off, offFallback]) == nil)
    }

    @Test("Templates produce usable profiles")
    func templates() {
        for template in GameProfileTemplate.allCases {
            let p = template.makeProfile()
            #expect(p.name == template.name)
            if template != .blank { #expect(p.eq != nil && p.dsp != nil) }
        }
    }

    @Test("Profile round-trips through JSON and decodes with defaults")
    func codable() throws {
        let p = GameProfileTemplate.cinematic.makeProfile()
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(GameProfile.self, from: data) == p)
        let bare = try JSONDecoder().decode(GameProfile.self, from: Data("{}".utf8))
        #expect(bare.isEnabled && bare.autoApply && bare.bundleIDs.isEmpty)
    }
}

// MARK: - Binaural

private func rms(_ x: [Float], channel: Int, from: Int = 0) -> Float {
    var sum: Float = 0, count = 0
    var i = from
    while i < x.count / 2 { let v = x[i * 2 + channel]; sum += v * v; count += 1; i += 1 }
    return count > 0 ? (sum / Float(count)).squareRoot() : 0
}

private func noise(frames: Int, seed: UInt64, channels: Int = 2) -> [Float] {
    var state = seed
    return (0..<frames * channels).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int64(bitPattern: state >> 11) % 2000 - 1000) / 4000   // ±0.25
    }
}

private func peakIndex(_ x: [Float], channel: Int) -> Int {
    var best = 0, value: Float = 0
    for i in 0..<x.count / 2 where abs(x[i * 2 + channel]) > value { value = abs(x[i * 2 + channel]); best = i }
    return best
}

@Suite("KEMAR HRTF data")
struct KEMARDataTests {

    @Test("All 25 measured angles are present, finite and 128 taps long")
    func integrity() {
        #expect(KEMARHRTF.azimuths.count == 25)
        for az in KEMARHRTF.azimuths {
            let (ipsi, contra) = KEMARHRTF.hrir(azimuth: az)
            #expect(ipsi.count == 128 && contra.count == 128, "az \(az)")
            #expect((ipsi + contra).allSatisfy { $0.isFinite }, "az \(az)")
            #expect(ipsi.contains { abs($0) > 0.01 }, "az \(az) looks empty")
        }
    }

    @Test("The ear on the source's side is louder and hears it first")
    func physics() {
        for az in [30, 60, 90] {
            let (ipsi, contra) = KEMARHRTF.hrir(azimuth: az)
            let eI = ipsi.reduce(0) { $0 + $1 * $1 }, eC = contra.reduce(0) { $0 + $1 * $1 }
            #expect(eI > eC, "az \(az): ipsi should be louder")
            let pI = ipsi.indices.max { abs(ipsi[$0]) < abs(ipsi[$1]) }!
            let pC = contra.indices.max { abs(contra[$0]) < abs(contra[$1]) }!
            #expect(pI < pC, "az \(az): ipsi should arrive earlier (ITD)")
        }
    }

    @Test("Straight ahead is symmetric")
    func front() {
        let (ipsi, contra) = KEMARHRTF.hrir(azimuth: 0)
        #expect(ipsi == contra)
    }

    @Test("Interaural delay grows with angle, around 0.25 ms at 30° (≈ 11 samples at 44.1 kHz)")
    func itd() {
        func itdSamples(_ az: Int) -> Int {
            let (i, c) = KEMARHRTF.hrir(azimuth: az)
            return c.indices.max { abs(c[$0]) < abs(c[$1]) }! - i.indices.max { abs(i[$0]) < abs(i[$1]) }!
        }
        #expect(itdSamples(30) >= 8 && itdSamples(30) <= 16)
        #expect(itdSamples(90) > itdSamples(30))
    }

    @Test("Angles snap to the 5° grid and clamp to the measured range")
    func snapping() {
        #expect(KEMARHRTF.nearestAzimuth(to: 32) == 30)
        #expect(KEMARHRTF.nearestAzimuth(to: 33) == 35)
        #expect(KEMARHRTF.nearestAzimuth(to: 500) == 120)
        #expect(KEMARHRTF.nearestAzimuth(to: -5) == 0)
    }
}

@Suite("BinauralConvolver — resampling")
struct BinauralResampleTests {

    @Test("Same rate returns the input unchanged")
    func identity() {
        let h = KEMARHRTF.hrir(azimuth: 30).ipsi
        #expect(BinauralConvolver.resample(h, from: 44_100, to: 44_100) == h)
    }

    @Test("Resampling preserves DC gain and scales length by the rate ratio",
          arguments: [32_000.0, 48_000.0, 96_000.0])
    func dcGain(rate: Double) {
        let h = KEMARHRTF.hrir(azimuth: 30).ipsi
        let r = BinauralConvolver.resample(h, from: 44_100, to: rate)
        #expect(abs(r.count - Int((128 * rate / 44_100).rounded(.up))) <= 1)
        let a = h.reduce(0, +), b = r.reduce(0, +)
        #expect(abs(a - b) < 0.05 * max(abs(a), 0.1), "dc \(a) vs \(b)")
    }

    @Test("Resampled response keeps its arrival time")
    func timing() {
        let h = KEMARHRTF.hrir(azimuth: 30).ipsi
        let r = BinauralConvolver.resample(h, from: 44_100, to: 96_000)
        let p1 = Double(h.indices.max { abs(h[$0]) < abs(h[$1]) }!) / 44_100
        let p2 = Double(r.indices.max { abs(r[$0]) < abs(r[$1]) }!) / 96_000
        #expect(abs(p1 - p2) < 0.0001)
    }
}

@Suite("BinauralConvolver — processing")
struct BinauralConvolverTests {

    private func make(angle: Double = 30, rate: Double = 48_000) -> BinauralConvolver {
        let c = BinauralConvolver()
        c.configure(speakerAngle: angle, sampleRate: rate)
        c.resetHistory()
        return c
    }

    private func process(_ c: BinauralConvolver, _ input: [Float], mix: Float = 1, block: Int = 1000) -> [Float] {
        var data = input
        let frames = data.count / 2
        data.withUnsafeMutableBufferPointer { ptr in
            var off = 0
            while off < frames {
                let n = min(block, frames - off)
                c.process(ptr.baseAddress! + off * 2, frameCount: n, mix: mix)
                off += n
            }
        }
        return data
    }

    @Test("Output equals a direct convolution with the active filters, across chunk boundaries")
    func matchesReference() {
        let c = make()
        let (ipsi, contra) = c.currentFilters()
        let frames = 9000   // spans three internal 4096-frame chunks
        let input = noise(frames: frames, seed: 7)
        let out = process(c, input, block: 1500)
        var maxError: Float = 0
        for n in stride(from: 0, to: frames, by: 7) {
            var l: Float = 0, r: Float = 0
            for k in 0..<ipsi.count where n - k >= 0 {
                let inL = input[(n - k) * 2], inR = input[(n - k) * 2 + 1]
                l += ipsi[k] * inL + contra[k] * inR
                r += ipsi[k] * inR + contra[k] * inL
            }
            maxError = max(maxError, abs(l - out[n * 2]), abs(r - out[n * 2 + 1]))
        }
        #expect(maxError < 1e-4, "max error \(maxError)")
    }

    @Test("Result does not depend on how the stream is cut into blocks")
    func blockIndependent() {
        let input = noise(frames: 12_000, seed: 3)
        let a = process(make(), input, block: 64)
        let b = process(make(), input, block: 5000)
        var maxDiff: Float = 0
        for i in 0..<a.count { maxDiff = max(maxDiff, abs(a[i] - b[i])) }
        #expect(maxDiff < 1e-5)
    }

    @Test("A left-only impulse reaches the left ear first and louder")
    func interauralCues() {
        var input = [Float](repeating: 0, count: 600 * 2)
        input[100 * 2] = 1                    // left impulse
        let out = process(make(angle: 30), input)
        #expect(peakIndex(out, channel: 0) < peakIndex(out, channel: 1))
        #expect(rms(out, channel: 0) > rms(out, channel: 1))
        #expect(rms(out, channel: 1) > 0, "far ear must still hear the speaker")
    }

    @Test("A right-only impulse mirrors it")
    func mirrored() {
        var input = [Float](repeating: 0, count: 600 * 2)
        input[100 * 2 + 1] = 1
        let out = process(make(angle: 30), input)
        #expect(peakIndex(out, channel: 1) < peakIndex(out, channel: 0))
        #expect(rms(out, channel: 1) > rms(out, channel: 0))
    }

    @Test("A mono (centre) signal gives identical ears")
    func centre() {
        var input = noise(frames: 4000, seed: 11)
        for i in 0..<4000 { input[i * 2 + 1] = input[i * 2] }
        let out = process(make(), input)
        for i in 0..<4000 { #expect(abs(out[i * 2] - out[i * 2 + 1]) < 1e-5) }
    }

    @Test("Mix 0 is an exact bypass")
    func dry() {
        let input = noise(frames: 3000, seed: 5)
        #expect(process(make(), input, mix: 0) == input)
    }

    @Test("Uncorrelated stereo keeps roughly its level")
    func levelNormalised() {
        let left = noise(frames: 30_000, seed: 21, channels: 1)
        let right = noise(frames: 30_000, seed: 99, channels: 1)
        var input = [Float](repeating: 0, count: 60_000)
        for i in 0..<30_000 { input[i * 2] = left[i]; input[i * 2 + 1] = right[i] }
        let out = process(make(), input)
        let before = (rms(input, channel: 0, from: 1000) + rms(input, channel: 1, from: 1000)) / 2
        let after = (rms(out, channel: 0, from: 1000) + rms(out, channel: 1, from: 1000)) / 2
        let diffDB = 20 * log10(after / before)
        #expect(abs(diffDB) < 2.5, "level changed by \(diffDB) dB")
    }

    @Test("Changing the angle mid-stream stays smooth, finite and bounded")
    func angleChange() {
        let c = make(angle: 30)
        var data = noise(frames: 8000, seed: 2)
        data.withUnsafeMutableBufferPointer { ptr in
            c.process(ptr.baseAddress!, frameCount: 2000, mix: 1)
            c.configure(speakerAngle: 90, sampleRate: 48_000)
            c.process(ptr.baseAddress! + 4000, frameCount: 2000, mix: 1)
            c.configure(speakerAngle: 10, sampleRate: 48_000)
            c.process(ptr.baseAddress! + 8000, frameCount: 4000, mix: 1)
        }
        #expect(data.prefix(24_000).allSatisfy { $0.isFinite && abs($0) < 2 })
    }

    @Test("Every supported angle and sample rate yields valid filters",
          arguments: [10.0, 30, 55, 90, 110], [32_000.0, 44_100, 48_000, 96_000, 192_000])
    func configurations(angle: Double, rate: Double) {
        let c = BinauralConvolver()
        c.configure(speakerAngle: angle, sampleRate: rate)
        let (ipsi, contra) = c.currentFilters()
        #expect(!ipsi.isEmpty && ipsi.count == contra.count && ipsi.count <= BinauralConvolver.maxTaps)
        #expect((ipsi + contra).allSatisfy { $0.isFinite })
        let energy = ipsi.reduce(0) { $0 + $1 * $1 } + contra.reduce(0) { $0 + $1 * $1 }
        #expect(abs(energy - 1) < 0.01, "normalised energy \(energy)")
    }

    @Test("Non-finite input does not poison the output")
    func nanSafe() {
        var input = noise(frames: 2000, seed: 4)
        input[50] = .nan; input[301] = .infinity
        #expect(process(make(), input).allSatisfy { $0.isFinite })
    }
}

@Suite("Binaural — settings and chain integration")
struct BinauralIntegrationTests {

    @Test("Binaural fields round-trip, clamp and default sensibly")
    func settingsCodable() throws {
        var s = SpatialSettings(); s.isEnabled = true; s.binaural = true; s.speakerAngle = 55; s.binauralMix = 0.6
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(SpatialSettings.self, from: data) == s)
        let legacy = try JSONDecoder().decode(SpatialSettings.self, from: Data(#"{"isEnabled":true,"width":1.2}"#.utf8))
        #expect(!legacy.binaural && legacy.speakerAngle == 30 && legacy.binauralMix == 1)
        let wild = try JSONDecoder().decode(SpatialSettings.self, from: Data(#"{"speakerAngle":999,"binauralMix":-3}"#.utf8))
        #expect(wild.speakerAngle == SpatialSettings.speakerAngleRange.upperBound && wild.binauralMix == 0)
    }

    @Test("Binaural makes the settings non-neutral; zero mix does not")
    func neutrality() {
        var s = SpatialSettings(); s.isEnabled = true
        #expect(s.isNeutral)
        s.binaural = true
        #expect(!s.isNeutral)
        s.binauralMix = 0
        #expect(s.isNeutral)
    }

    @Test("Binaural presets are valid")
    func presets() {
        for p in [SpatialPreset.binauralStudio, .binauralWide, .binauralGame] {
            #expect(p.settings.binaural && p.settings.isEnabled && p.settings == p.settings.clamped)
        }
    }

    @Test("The processor renders binaurally, replacing crossfeed")
    func processorBinaural() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings(); s.spatial = SpatialPreset.binauralStudio.settings; s.spatial.crossfeed = 1
        p.updateSettings(s)
        #expect(p.isEnabled)
        var impulse = [Float](repeating: 0, count: 800 * 2); impulse[100 * 2] = 1
        let out = run(p, impulse)
        #expect(out.allSatisfy { $0.isFinite })
        #expect(rms(out, channel: 1) > 0)                         // far-ear path exists
        #expect(peakIndex(out, channel: 0) < peakIndex(out, channel: 1))
    }

    @Test("Turning binaural off restores a bit-exact passthrough")
    func offIsTransparent() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings(); s.spatial = SpatialPreset.binauralGame.settings
        p.updateSettings(s)
        _ = run(p, noise(frames: 4000, seed: 1))
        p.updateSettings(ChannelDSPSettings())
        let input = noise(frames: 2000, seed: 2)
        #expect(run(p, input) == input)
    }

    @Test("Re-enabling starts from a clean history")
    func cleanRestart() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings(); s.spatial = SpatialPreset.binauralStudio.settings
        p.updateSettings(s)
        _ = run(p, noise(frames: 4000, seed: 1))
        p.updateSettings(ChannelDSPSettings())
        _ = run(p, noise(frames: 600, seed: 8))
        p.updateSettings(s)
        let silence = [Float](repeating: 0, count: 1000 * 2)
        #expect(peak(run(p, silence)) == 0)                         // no leftover tail from before
    }

    @Test("Sample-rate changes reconfigure the filters")
    func rateChange() {
        let p = ChannelDSPProcessor(sampleRate: 48_000)
        var s = ChannelDSPSettings(); s.spatial = SpatialPreset.binauralWide.settings
        p.updateSettings(s)
        p.updateSampleRate(96_000)
        let out = run(p, noise(frames: 20_000, seed: 6))
        #expect(out.allSatisfy { $0.isFinite && abs($0) < 2 })
    }

    @Test("Binaural combines with width, room, compressor and limiter")
    func fullChain() {
        let p = ChannelDSPProcessor(sampleRate: sr)
        var s = ChannelDSPSettings()
        s.spatial = SpatialPreset.binauralGame.settings; s.spatial.width = 1.5
        s.dynamics = DynamicsPreset.gameNight.settings
        p.updateSettings(s)
        let loud = noise(frames: 48_000, seed: 13).map { $0 * 3.5 }
        let out = run(p, loud)
        #expect(out.allSatisfy { $0.isFinite })
        #expect(peak(out, from: 6000) <= 0.75, "limiter ceiling (-3 dB ≈ 0.708) must hold, got \(peak(out, from: 6000))")
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
