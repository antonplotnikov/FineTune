import Foundation

nonisolated struct EQSettings: Codable, Equatable {
    static let bandCount = 10
    static let maxGainDB: Float = 18.0
    static let minGainDB: Float = -18.0
    /// Preamp range (dB): mostly negative headroom for boosted curves, a little positive makeup.
    static let minPreampDB: Float = -18.0
    static let maxPreampDB: Float = 6.0
    /// Fine-adjust resolution for sliders (dB)
    static let gainStepDB: Float = 0.1

    /// ISO standard frequencies for 10-band graphic EQ
    static let frequencies: [Double] = [
        31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    /// Gain in dB for each band (-18 to +18)
    var bandGains: [Float]

    /// Whether EQ processing is enabled
    var isEnabled: Bool

    /// Which band model drives the audio path.
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case graphic, parametric
        var id: String { rawValue }
        var title: String { self == .graphic ? "Graphic" : "Parametric" }
    }

    /// `.graphic` uses `bandGains` at fixed centers; `.parametric` uses `parametricBands`.
    var mode: Mode

    /// Fully adjustable bands (at most `bandCount`), used when `mode == .parametric`.
    var parametricBands: [ParametricBand]

    /// Output gain applied with the curve (either mode), used to keep boosted curves from clipping.
    var preampDB: Float

    /// Parameters of the Radio Vibe wall effect that generated the current curve, if any.
    var wallEffect: WallEffect?

    init(bandGains: [Float] = Array(repeating: 0, count: 10), isEnabled: Bool = true,
         mode: Mode = .graphic, parametricBands: [ParametricBand] = ParametricBand.defaultBands,
         preampDB: Float = 0) {
        self.bandGains = Self.normalizeBands(bandGains)
        self.isEnabled = isEnabled
        self.mode = mode
        self.parametricBands = Array(parametricBands.prefix(Self.bandCount))
        self.preampDB = Self.clampPreamp(preampDB)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([Float].self, forKey: .bandGains)
            ?? Array(repeating: 0, count: Self.bandCount)
        self.bandGains = Self.normalizeBands(decoded)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .graphic
        let bands = try container.decodeIfPresent([ParametricBand].self, forKey: .parametricBands)
        self.parametricBands = Array((bands ?? ParametricBand.defaultBands).prefix(Self.bandCount))
        self.preampDB = Self.clampPreamp(try container.decodeIfPresent(Float.self, forKey: .preampDB) ?? 0)
        self.wallEffect = try container.decodeIfPresent(WallEffect.self, forKey: .wallEffect)
    }

    static func clampPreamp(_ value: Float) -> Float {
        value.isFinite ? max(minPreampDB, min(maxPreampDB, value)) : 0
    }

    /// Normalize band gains array to exactly `bandCount` elements,
    /// padding with 0 or truncating as needed.
    private static func normalizeBands(_ gains: [Float]) -> [Float] {
        if gains.count == bandCount { return gains }
        if gains.count > bandCount { return Array(gains.prefix(bandCount)) }
        return gains + Array(repeating: Float(0), count: bandCount - gains.count)
    }

    /// Returns gains clamped to valid range
    var clampedGains: [Float] {
        bandGains.map { $0.isFinite ? max(Self.minGainDB, min(Self.maxGainDB, $0)) : 0 }
    }

    /// Parametric bands with every value clamped to its valid range.
    var clampedParametricBands: [ParametricBand] {
        parametricBands.map {
            ParametricBand(id: $0.id, isEnabled: $0.isEnabled, type: $0.type,
                           frequency: $0.frequency, gainDB: $0.gainDB, q: $0.q)
        }
    }

    /// True when both settings describe the same curve (ignores `isEnabled` and band identity).
    func hasSameCurve(as other: EQSettings) -> Bool {
        guard mode == other.mode, preampDB == other.preampDB else { return false }
        switch mode {
        case .graphic:
            return bandGains == other.bandGains
        case .parametric:
            func shape(_ b: ParametricBand) -> [Double] {
                [b.isEnabled ? 1 : 0, Double(EQFilterType.allCases.firstIndex(of: b.type) ?? 0),
                 b.frequency, Double(b.gainDB), b.q]
            }
            return parametricBands.map(shape) == other.parametricBands.map(shape)
        }
    }

    /// Copies the curve (mode, gains, bands) from `preset`, keeping this value's `isEnabled`.
    func applyingCurve(from preset: EQSettings) -> EQSettings {
        var result = preset
        result.isEnabled = isEnabled
        return result
    }

    /// Switches to parametric mode; if the parametric bands are still the untouched defaults,
    /// seeds them from the current graphic gains so the curve carries over.
    mutating func switchMode(to newMode: Mode) {
        guard newMode != mode else { return }
        if newMode == .parametric,
           parametricBands.allSatisfy({ $0.gainDB == 0 && $0.type == .peaking && $0.q == ParametricBand.defaultQ }) {
            for index in parametricBands.indices where index < bandGains.count {
                parametricBands[index].gainDB = ParametricBand.clampGain(bandGains[index])
            }
        }
        mode = newMode
    }

    /// True when the EQ changes nothing (or is switched off): flat gains/bands and no preamp.
    var isFlat: Bool {
        guard isEnabled else { return true }
        guard preampDB == 0 else { return false }
        switch mode {
        case .graphic: return clampedGains.allSatisfy { $0 == 0 }
        case .parametric: return parametricBands.allSatisfy(\.isNeutral)
        }
    }

    /// Flat EQ preset
    static let flat = EQSettings()
}
