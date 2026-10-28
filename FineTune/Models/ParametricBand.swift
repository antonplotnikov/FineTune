import Foundation

/// Filter shapes available to a parametric EQ band (RBJ cookbook biquads).
nonisolated enum EQFilterType: String, Codable, CaseIterable, Identifiable {
    case peaking, lowShelf, highShelf, highPass, lowPass, notch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peaking: return "Peak"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .highPass: return "High Pass"
        case .lowPass: return "Low Pass"
        case .notch: return "Notch"
        }
    }

    /// Whether the band's gain value affects the filter.
    var usesGain: Bool {
        switch self {
        case .peaking, .lowShelf, .highShelf: return true
        case .highPass, .lowPass, .notch: return false
        }
    }

    /// Web Audio `BiquadFilterNode.type` for the browser extension.
    var webAudioType: String {
        switch self {
        case .peaking: return "peaking"
        case .lowShelf: return "lowshelf"
        case .highShelf: return "highshelf"
        case .highPass: return "highpass"
        case .lowPass: return "lowpass"
        case .notch: return "notch"
        }
    }
}

/// One fully adjustable EQ band: type, frequency, gain and Q.
nonisolated struct ParametricBand: Codable, Equatable, Identifiable {
    static let minFrequency: Double = 20
    static let maxFrequency: Double = 20_000
    static let minQ: Double = 0.1
    static let maxQ: Double = 20
    static let defaultQ: Double = 1.4

    var id: UUID
    var isEnabled: Bool
    var type: EQFilterType
    var frequency: Double
    var gainDB: Float
    var q: Double

    init(id: UUID = UUID(), isEnabled: Bool = true, type: EQFilterType = .peaking,
         frequency: Double = 1000, gainDB: Float = 0, q: Double = ParametricBand.defaultQ) {
        self.id = id
        self.isEnabled = isEnabled
        self.type = type
        self.frequency = Self.clampFrequency(frequency)
        self.gainDB = Self.clampGain(gainDB)
        self.q = Self.clampQ(q)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            type: try c.decodeIfPresent(EQFilterType.self, forKey: .type) ?? .peaking,
            frequency: try c.decodeIfPresent(Double.self, forKey: .frequency) ?? 1000,
            gainDB: try c.decodeIfPresent(Float.self, forKey: .gainDB) ?? 0,
            q: try c.decodeIfPresent(Double.self, forKey: .q) ?? Self.defaultQ
        )
    }

    static func clampFrequency(_ f: Double) -> Double {
        f.isFinite ? max(minFrequency, min(maxFrequency, f)) : 1000
    }
    static func clampGain(_ g: Float) -> Float {
        g.isFinite ? max(EQSettings.minGainDB, min(EQSettings.maxGainDB, g)) : 0
    }
    static func clampQ(_ q: Double) -> Double {
        q.isFinite ? max(minQ, min(maxQ, q)) : defaultQ
    }

    /// True when the band leaves the signal untouched.
    var isNeutral: Bool {
        !isEnabled || (type.usesGain && abs(gainDB) < 0.001)
    }

    /// The ten default bands: same centers as the graphic EQ, flat.
    /// Builds bands with fixed ids, for built-in presets (so equal presets compare equal).
    static func preset(_ specs: [(EQFilterType, Double, Float, Double)]) -> [ParametricBand] {
        specs.enumerated().map { index, spec in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index + 1)) ?? UUID()
            return ParametricBand(id: id, type: spec.0, frequency: spec.1, gainDB: spec.2, q: spec.3)
        }
    }

    /// IDs are fixed so two untouched `EQSettings` compare equal.
    static var defaultBands: [ParametricBand] {
        EQSettings.frequencies.enumerated().map { index, frequency in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID()
            return ParametricBand(id: id, frequency: frequency)
        }
    }
}
