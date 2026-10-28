import Foundation

/// Compressor + limiter settings for one app channel.
nonisolated struct DynamicsSettings: Codable, Equatable, Sendable {
    static let thresholdRange: ClosedRange<Double> = -60...0
    static let ratioRange: ClosedRange<Double> = 1...20
    static let attackRange: ClosedRange<Double> = 0.1...200
    static let releaseRange: ClosedRange<Double> = 10...2000
    static let kneeRange: ClosedRange<Double> = 0...24
    static let makeupRange: ClosedRange<Double> = 0...24
    static let ceilingRange: ClosedRange<Double> = -12...0
    static let limiterReleaseRange: ClosedRange<Double> = 10...500

    var compressorEnabled = false
    var thresholdDB: Double = -18
    var ratio: Double = 3
    var attackMs: Double = 10
    var releaseMs: Double = 120
    var kneeDB: Double = 6
    var makeupDB: Double = 0

    var limiterEnabled = false
    var ceilingDB: Double = -1
    var limiterReleaseMs: Double = 60

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get(_ key: CodingKeys, _ range: ClosedRange<Double>, _ fallback: Double) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
            return value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        compressorEnabled = try c.decodeIfPresent(Bool.self, forKey: .compressorEnabled) ?? false
        thresholdDB = try get(.thresholdDB, Self.thresholdRange, -18)
        ratio = try get(.ratio, Self.ratioRange, 3)
        attackMs = try get(.attackMs, Self.attackRange, 10)
        releaseMs = try get(.releaseMs, Self.releaseRange, 120)
        kneeDB = try get(.kneeDB, Self.kneeRange, 6)
        makeupDB = try get(.makeupDB, Self.makeupRange, 0)
        limiterEnabled = try c.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? false
        ceilingDB = try get(.ceilingDB, Self.ceilingRange, -1)
        limiterReleaseMs = try get(.limiterReleaseMs, Self.limiterReleaseRange, 60)
    }

    /// Returns a copy with every value clamped to its valid range.
    var clamped: DynamicsSettings {
        var s = self
        func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound }
        s.thresholdDB = clamp(thresholdDB, Self.thresholdRange)
        s.ratio = clamp(ratio, Self.ratioRange)
        s.attackMs = clamp(attackMs, Self.attackRange)
        s.releaseMs = clamp(releaseMs, Self.releaseRange)
        s.kneeDB = clamp(kneeDB, Self.kneeRange)
        s.makeupDB = clamp(makeupDB, Self.makeupRange)
        s.ceilingDB = clamp(ceilingDB, Self.ceilingRange)
        s.limiterReleaseMs = clamp(limiterReleaseMs, Self.limiterReleaseRange)
        return s
    }

    var isActive: Bool { compressorEnabled || limiterEnabled }
}

/// Headphone-oriented stereo imaging: width, crossfeed (speaker-like leakage) and a touch of room.
nonisolated struct SpatialSettings: Codable, Equatable, Sendable {
    static let widthRange: ClosedRange<Double> = 0...2
    static let amountRange: ClosedRange<Double> = 0...1
    /// Virtual speaker azimuth (degrees from straight ahead). The HRTF set is measured on a 5° grid.
    static let speakerAngleRange: ClosedRange<Double> = 10...110

    var isEnabled = false
    /// Stereo width: 1 = unchanged, 0 = mono, 2 = twice as wide.
    var width: Double = 1
    /// Amount of delayed, low-passed opposite-channel signal (like listening to speakers).
    var crossfeed: Double = 0
    /// Amount of short early reflections for a sense of space.
    var room: Double = 0

    /// Binaural rendering: the stereo signal is placed on two virtual speakers using measured
    /// head-related transfer functions. Replaces crossfeed; intended for headphones.
    var binaural = false
    /// Azimuth of each virtual speaker in degrees (30° = a classic stereo triangle).
    var speakerAngle: Double = 30
    /// Dry/wet blend of the binaural rendering.
    var binauralMix: Double = 1

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get(_ key: CodingKeys, _ range: ClosedRange<Double>, _ fallback: Double) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
            return value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        width = try get(.width, Self.widthRange, 1)
        crossfeed = try get(.crossfeed, Self.amountRange, 0)
        room = try get(.room, Self.amountRange, 0)
        binaural = try c.decodeIfPresent(Bool.self, forKey: .binaural) ?? false
        speakerAngle = try get(.speakerAngle, Self.speakerAngleRange, 30)
        binauralMix = try get(.binauralMix, Self.amountRange, 1)
    }

    var clamped: SpatialSettings {
        var s = self
        func clamp(_ v: Double, _ r: ClosedRange<Double>, _ fallback: Double) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : fallback }
        s.width = clamp(width, Self.widthRange, 1)
        s.crossfeed = clamp(crossfeed, Self.amountRange, 0)
        s.room = clamp(room, Self.amountRange, 0)
        s.speakerAngle = clamp(speakerAngle, Self.speakerAngleRange, 30)
        s.binauralMix = clamp(binauralMix, Self.amountRange, 1)
        return s
    }

    /// True when enabling would change nothing audible.
    var isNeutral: Bool { !isEnabled || (width == 1 && crossfeed == 0 && room == 0 && !(binaural && binauralMix > 0)) }
}

/// Per-app dynamics and spatial processing, applied after the EQ.
nonisolated struct ChannelDSPSettings: Codable, Equatable, Sendable {
    var dynamics = DynamicsSettings()
    var spatial = SpatialSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dynamics = try c.decodeIfPresent(DynamicsSettings.self, forKey: .dynamics) ?? DynamicsSettings()
        spatial = try c.decodeIfPresent(SpatialSettings.self, forKey: .spatial) ?? SpatialSettings()
    }

    static let off = ChannelDSPSettings()

    /// True when nothing is enabled, so the audio thread can skip the processor entirely.
    var isInactive: Bool { !dynamics.isActive && spatial.isNeutral }
}

// MARK: - Presets

nonisolated enum DynamicsPreset: String, CaseIterable, Identifiable {
    case off, gentleLeveler, gameNight, voiceLeveler, limiterOnly, hardLimit

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return "Off"
        case .gentleLeveler: return "Gentle Leveler"
        case .gameNight: return "Game Night"
        case .voiceLeveler: return "Voice Leveler"
        case .limiterOnly: return "Limiter Only"
        case .hardLimit: return "Hard Limit (-6 dB)"
        }
    }

    var settings: DynamicsSettings {
        var s = DynamicsSettings()
        switch self {
        case .off:
            break
        case .gentleLeveler:
            s.compressorEnabled = true
            s.thresholdDB = -20; s.ratio = 2; s.attackMs = 20; s.releaseMs = 250; s.kneeDB = 10; s.makeupDB = 2
            s.limiterEnabled = true; s.ceilingDB = -1; s.limiterReleaseMs = 80
        case .gameNight:
            // Heavy squash: quiet footsteps stay audible, explosions don't wake the house.
            s.compressorEnabled = true
            s.thresholdDB = -30; s.ratio = 6; s.attackMs = 5; s.releaseMs = 200; s.kneeDB = 8; s.makeupDB = 9
            s.limiterEnabled = true; s.ceilingDB = -3; s.limiterReleaseMs = 100
        case .voiceLeveler:
            s.compressorEnabled = true
            s.thresholdDB = -24; s.ratio = 4; s.attackMs = 8; s.releaseMs = 150; s.kneeDB = 6; s.makeupDB = 5
            s.limiterEnabled = true; s.ceilingDB = -1.5; s.limiterReleaseMs = 60
        case .limiterOnly:
            s.limiterEnabled = true; s.ceilingDB = -1; s.limiterReleaseMs = 60
        case .hardLimit:
            s.limiterEnabled = true; s.ceilingDB = -6; s.limiterReleaseMs = 40
        }
        return s
    }
}

nonisolated enum SpatialPreset: String, CaseIterable, Identifiable {
    case off, wideStage, headphoneCrossfeed, virtualSurround, arena, binauralStudio, binauralWide, binauralGame

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return "Off"
        case .wideStage: return "Wide Stage"
        case .headphoneCrossfeed: return "Headphone Crossfeed"
        case .virtualSurround: return "Virtual Surround"
        case .arena: return "Arena"
        case .binauralStudio: return "Binaural Studio (30°)"
        case .binauralWide: return "Binaural Wide (55°)"
        case .binauralGame: return "Binaural Game"
        }
    }

    var settings: SpatialSettings {
        var s = SpatialSettings()
        switch self {
        case .off:
            break
        case .wideStage:
            s.isEnabled = true; s.width = 1.5
        case .headphoneCrossfeed:
            s.isEnabled = true; s.crossfeed = 0.45
        case .virtualSurround:
            s.isEnabled = true; s.width = 1.35; s.crossfeed = 0.3; s.room = 0.35
        case .arena:
            s.isEnabled = true; s.width = 1.6; s.crossfeed = 0.2; s.room = 0.7
        case .binauralStudio:
            s.isEnabled = true; s.binaural = true; s.speakerAngle = 30
        case .binauralWide:
            s.isEnabled = true; s.binaural = true; s.speakerAngle = 55
        case .binauralGame:
            // Wider stage plus a little room: footsteps and gunfire land outside the head.
            s.isEnabled = true; s.binaural = true; s.speakerAngle = 45; s.room = 0.25
        }
        return s
    }
}
