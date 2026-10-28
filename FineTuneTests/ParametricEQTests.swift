// FineTuneTests/ParametricEQTests.swift
// Parametric EQ model, coefficient math, response curve, and persistence compatibility.

import Testing
import Foundation
@testable import FineTune

@Suite("ParametricBand — model")
struct ParametricBandModelTests {

    @Test("Values are clamped to valid ranges")
    func clamps() {
        let b = ParametricBand(frequency: 5, gainDB: 99, q: 500)
        #expect(b.frequency == ParametricBand.minFrequency)
        #expect(b.gainDB == EQSettings.maxGainDB)
        #expect(b.q == ParametricBand.maxQ)
        #expect(ParametricBand(frequency: .nan, gainDB: .nan, q: .nan).gainDB == 0)
    }

    @Test("Neutral detection")
    func neutral() {
        #expect(ParametricBand(gainDB: 0).isNeutral)
        #expect(!ParametricBand(gainDB: 3).isNeutral)
        #expect(ParametricBand(isEnabled: false, gainDB: 6).isNeutral)
        #expect(!ParametricBand(type: .highPass, gainDB: 0).isNeutral)
    }

    @Test("Untouched default settings are equal (stable band ids)")
    func defaultsEqual() {
        #expect(EQSettings() == EQSettings())
        #expect(EQSettings.flat == EQSettings())
    }

    @Test("Default bands mirror the graphic centers")
    func defaults() {
        #expect(ParametricBand.defaultBands.map(\.frequency) == EQSettings.frequencies)
    }
}

@Suite("EQSettings — parametric mode")
struct EQSettingsParametricTests {

    @Test("Legacy JSON without mode decodes as graphic with default bands")
    func legacyDecode() throws {
        let json = #"{"bandGains":[1,2,3,4,5,6,7,8,9,10],"isEnabled":true}"#
        let eq = try JSONDecoder().decode(EQSettings.self, from: Data(json.utf8))
        #expect(eq.mode == .graphic)
        #expect(eq.parametricBands.count == EQSettings.bandCount)
        #expect(eq.bandGains[9] == 10)
    }

    @Test("Parametric settings round-trip through JSON")
    func roundTrip() throws {
        var eq = EQSettings()
        eq.mode = .parametric
        eq.parametricBands = [ParametricBand(type: .highPass, frequency: 80, q: 0.7),
                              ParametricBand(type: .highShelf, frequency: 8000, gainDB: -4.5)]
        let data = try JSONEncoder().encode(eq)
        let decoded = try JSONDecoder().decode(EQSettings.self, from: data)
        #expect(decoded == eq)
    }

    @Test("More than ten bands are truncated")
    func truncates() {
        let eq = EQSettings(mode: .parametric, parametricBands: Array(repeating: ParametricBand(), count: 14))
        #expect(eq.parametricBands.count == EQSettings.bandCount)
    }

    @Test("Switching to parametric seeds default bands from graphic gains")
    func seedsFromGraphic() {
        var eq = EQSettings(bandGains: [3, 0, 0, 0, 0, 0, 0, 0, 0, -2])
        eq.switchMode(to: .parametric)
        #expect(eq.mode == .parametric)
        #expect(eq.parametricBands[0].gainDB == 3)
        #expect(eq.parametricBands[9].gainDB == -2)
    }

    @Test("Switching does not overwrite customised parametric bands")
    func keepsCustomBands() {
        var eq = EQSettings(bandGains: [5, 5, 5, 5, 5, 5, 5, 5, 5, 5])
        eq.parametricBands[0] = ParametricBand(type: .lowShelf, frequency: 100, gainDB: 2)
        eq.switchMode(to: .parametric)
        #expect(eq.parametricBands[0].gainDB == 2)
    }

    @Test("hasSameCurve ignores isEnabled and band ids but not mode")
    func sameCurve() {
        let a = EQSettings(bandGains: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0], isEnabled: true)
        var b = a; b.isEnabled = false
        #expect(a.hasSameCurve(as: b))
        var c = a; c.mode = .parametric
        #expect(!a.hasSameCurve(as: c))
        var d = c; d.parametricBands = d.parametricBands.map { ParametricBand(isEnabled: $0.isEnabled, type: $0.type, frequency: $0.frequency, gainDB: $0.gainDB, q: $0.q) }
        #expect(c.hasSameCurve(as: d))
    }

    @Test("applyingCurve keeps the target's enabled state")
    func applyingCurve() {
        var target = EQSettings(); target.isEnabled = false
        var preset = EQSettings(); preset.mode = .parametric
        let result = target.applyingCurve(from: preset)
        #expect(result.mode == .parametric)
        #expect(result.isEnabled == false)
    }
}

@Suite("BiquadMath — parametric coefficients and response")
struct ParametricMathTests {
    private let sr = 48_000.0

    private func response(_ band: ParametricBand, at f: Double) -> Double {
        BiquadMath.magnitudeResponseDB(coefficients: BiquadMath.coefficients(for: band, sampleRate: sr), frequency: f, sampleRate: sr)
    }

    @Test("Peaking band reaches its gain at the center frequency")
    func peakGain() {
        let r = response(ParametricBand(type: .peaking, frequency: 1000, gainDB: 6, q: 1.4), at: 1000)
        #expect(abs(r - 6) < 0.05)
    }

    @Test("Shelves approach their gain far from the corner")
    func shelves() {
        #expect(abs(response(ParametricBand(type: .lowShelf, frequency: 200, gainDB: 5), at: 25) - 5) < 0.3)
        #expect(abs(response(ParametricBand(type: .highShelf, frequency: 4000, gainDB: -5), at: 18_000) + 5) < 0.3)
    }

    @Test("High-pass attenuates below, passes above; low-pass the reverse")
    func passFilters() {
        let hp = ParametricBand(type: .highPass, frequency: 200, q: 0.707)
        #expect(response(hp, at: 25) < -30)
        #expect(abs(response(hp, at: 5000)) < 0.5)
        let lp = ParametricBand(type: .lowPass, frequency: 5000, q: 0.707)
        #expect(response(lp, at: 20_000) < -20)
        #expect(abs(response(lp, at: 200)) < 0.5)
    }

    @Test("Notch removes the center frequency")
    func notch() {
        #expect(response(ParametricBand(type: .notch, frequency: 1000, q: 4), at: 1000) < -40)
    }

    @Test("Neutral, disabled and above-Nyquist bands are passthrough")
    func bypass() {
        for band in [ParametricBand(gainDB: 0), ParametricBand(isEnabled: false, gainDB: 9),
                     ParametricBand(frequency: 20_000, gainDB: 9)] {
            let c = BiquadMath.coefficients(for: band, sampleRate: 32_000)
            #expect(c == BiquadMath.unityCoefficients)
        }
    }

    @Test("Settings coefficients always cover ten sections and are finite")
    func fullSet() {
        var eq = EQSettings(); eq.mode = .parametric
        eq.parametricBands = [ParametricBand(type: .highPass, frequency: 60), ParametricBand(frequency: 3000, gainDB: 18, q: 20)]
        let c = BiquadMath.coefficients(for: eq, sampleRate: 44_100)
        #expect(c.count == 50)
        #expect(c.allSatisfy { $0.isFinite })
    }

    @Test("Graphic mode response matches existing band math")
    func graphicUnchanged() {
        let eq = EQSettings(bandGains: [0, 0, 0, 0, 0, 6, 0, 0, 0, 0])
        #expect(BiquadMath.coefficients(for: eq, sampleRate: sr)
                == BiquadMath.coefficientsForAllBands(gains: eq.clampedGains, sampleRate: sr))
    }
}

@Suite("EQ preamp")
struct EQPreampTests {
    private let sr = 48_000.0

    @Test("Preamp scales the overall response by its dB value")
    func preampScalesResponse() {
        var eq = EQSettings(); eq.preampDB = -6
        let c = BiquadMath.coefficients(for: eq, sampleRate: sr)
        let r = BiquadMath.magnitudeResponseDB(coefficients: c, frequency: 1000, sampleRate: sr)
        #expect(abs(r + 6) < 0.01)
    }

    @Test("Preamp is clamped and non-finite falls back to 0")
    func clamps() {
        #expect(EQSettings(preampDB: -99).preampDB == EQSettings.minPreampDB)
        #expect(EQSettings(preampDB: 99).preampDB == EQSettings.maxPreampDB)
        #expect(EQSettings(preampDB: .nan).preampDB == 0)
    }

    @Test("Peak boost finds the loudest point of the curve")
    func peakBoost() {
        var eq = EQSettings(); eq.mode = .parametric
        eq.parametricBands = [ParametricBand(frequency: 2000, gainDB: 8, q: 1.0)]
        #expect(abs(BiquadMath.peakBoostDB(for: eq) - 8) < 0.3)
    }

    @Test("Cut-only curves need no auto preamp")
    func cutOnly() {
        let eq = EQSettings(bandGains: [-6, -4, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(BiquadMath.autoPreampDB(for: eq) == 0)
    }

    @Test("Auto preamp cancels the boost, rounding toward more headroom")
    func autoPreamp() {
        var eq = EQSettings(); eq.mode = .parametric
        eq.parametricBands = [ParametricBand(frequency: 2000, gainDB: 8, q: 1.0)]
        let auto = BiquadMath.autoPreampDB(for: eq)
        #expect(auto <= -7.7 && auto >= -8.5)
        eq.preampDB = auto
        let c = BiquadMath.coefficients(for: eq, sampleRate: sr)
        let r = BiquadMath.magnitudeResponseDB(coefficients: c, frequency: 2000, sampleRate: sr)
        #expect(r <= 0.1)
    }

    @Test("Preamp round-trips through JSON and defaults to 0 for old files")
    func persistence() throws {
        var eq = EQSettings(); eq.preampDB = -4.5
        let data = try JSONEncoder().encode(eq)
        #expect(try JSONDecoder().decode(EQSettings.self, from: data).preampDB == -4.5)
        let legacy = try JSONDecoder().decode(EQSettings.self, from: Data(#"{"bandGains":[0,0,0,0,0,0,0,0,0,0]}"#.utf8))
        #expect(legacy.preampDB == 0)
    }

    @Test("Preamp participates in curve comparison")
    func comparison() {
        let a = EQSettings(); var b = a; b.preampDB = -3
        #expect(!a.hasSameCurve(as: b))
    }
}

@Suite("SpectrumAnalyzer")
@MainActor
struct SpectrumAnalyzerTests {

    private func feedSine(_ tap: SpectrumTap, frequency: Double, amplitude: Float, seconds: Double = 0.2) {
        let rate = tap.sampleRate
        let count = Int(rate * seconds)
        var samples = [Float](repeating: 0, count: count * 2)  // stereo interleaved
        for i in 0..<count {
            let v = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / rate))
            samples[i * 2] = v; samples[i * 2 + 1] = v
        }
        samples.withUnsafeBufferPointer { tap.capture(samples: $0.baseAddress!, frameCount: count, channels: 2) }
    }

    private func pointIndex(for frequency: Double) -> Int {
        let lo = log10(ParametricBand.minFrequency), hi = log10(ParametricBand.maxFrequency)
        return Int((log10(frequency) - lo) / (hi - lo) * Double(SpectrumAnalyzer.pointCount))
    }

    @Test("Capture is a no-op until enabled")
    func gated() {
        let tap = SpectrumTap()
        feedSine(tap, frequency: 1000, amplitude: 0.5)
        #expect(tap.writeIndex == 0)
    }

    @Test("A 1 kHz sine peaks at the 1 kHz point at about its level")
    func detectsSine() {
        let tap = SpectrumTap(); tap.isCapturing = true
        feedSine(tap, frequency: 1000, amplitude: 0.5)
        let db = SpectrumAnalyzer(tap: tap).snapshot()
        #expect(db.count == SpectrumAnalyzer.pointCount)
        let peakIndex = db.indices.max { db[$0] < db[$1] }!
        #expect(abs(peakIndex - pointIndex(for: 1000)) <= 2)
        // 0.5 amplitude ≈ -6 dBFS; Hann window and bin binning allow a few dB of slack.
        #expect(db[peakIndex] > -12 && db[peakIndex] < 0)
    }

    @Test("Silence stays at the floor")
    func silence() {
        let tap = SpectrumTap(); tap.isCapturing = true
        feedSine(tap, frequency: 1000, amplitude: 0)
        let db = SpectrumAnalyzer(tap: tap).snapshot()
        #expect(db.allSatisfy { $0 <= SpectrumAnalyzer.floorDB + 1 })
    }
}

@Suite("EQ edit session")
struct EQEditSessionTests {
    private func eq(_ gain: Float) -> EQSettings { EQSettings(bandGains: [gain] + Array(repeating: 0, count: 9)) }
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("Rapid edits coalesce into one undo step")
    func coalesce() {
        var h = EQEditHistory()
        h.record(previous: eq(0), now: t0)
        h.record(previous: eq(1), now: t0.addingTimeInterval(0.1))
        h.record(previous: eq(2), now: t0.addingTimeInterval(0.2))
        #expect(h.undoStack.count == 1)
        #expect(h.undo(current: eq(3)) == eq(0))
    }

    @Test("Edits after a pause become separate steps")
    func separateSteps() {
        var h = EQEditHistory()
        h.record(previous: eq(0), now: t0)
        h.record(previous: eq(1), now: t0.addingTimeInterval(2))
        #expect(h.undoStack.count == 2)
    }

    @Test("Undo then redo restores the value; a new edit clears redo")
    func undoRedo() {
        var h = EQEditHistory()
        h.record(previous: eq(0), now: t0)
        #expect(h.undo(current: eq(5)) == eq(0))
        #expect(h.canRedo)
        #expect(h.redo(current: eq(0)) == eq(5))
        _ = h.undo(current: eq(5))
        h.record(previous: eq(0), now: t0.addingTimeInterval(5))
        #expect(!h.canRedo)
    }

    @Test("Undo on an empty history is nil and the stack is capped")
    func emptyAndCap() {
        var h = EQEditHistory(limit: 3)
        #expect(h.undo(current: eq(0)) == nil)
        for i in 0..<10 { h.record(previous: eq(Float(i)), now: t0.addingTimeInterval(Double(i) * 5)) }
        #expect(h.undoStack.count == 3)
        #expect(h.undoStack.first == eq(7))
    }

    @Test("A/B keeps both curves and flips between them")
    func abCompare() {
        var ab = EQABCompare()
        ab.begin(current: eq(1))
        #expect(ab.activeSlot == .b)
        ab.store(current: eq(6))                       // user edits B
        #expect(ab.toggle(current: eq(6)) == eq(1))    // back to original A
        #expect(ab.activeSlot == .a)
        #expect(ab.toggle(current: eq(1)) == eq(6))    // forward to edited B
    }

    @Test("A/B is inert until begun and ends cleanly")
    func abInert() {
        var ab = EQABCompare()
        #expect(ab.toggle(current: eq(2)) == eq(2))
        ab.begin(current: eq(2)); ab.end()
        #expect(!ab.isActive)
    }

    @Test("Clipboard round-trips a parametric curve and rejects other text")
    func clipboard() throws {
        var source = EQSettings(); source.mode = .parametric; source.preampDB = -3
        source.parametricBands = [ParametricBand(type: .highShelf, frequency: 8000, gainDB: 4)]
        let text = try #require(source.clipboardString)
        let parsed = try #require(EQSettings.fromClipboard(text))
        #expect(parsed.hasSameCurve(as: source))
        #expect(EQSettings.fromClipboard("hello") == nil)
        #expect(EQSettings.fromClipboard(#"{"foo":1}"#) == nil)
    }
}
