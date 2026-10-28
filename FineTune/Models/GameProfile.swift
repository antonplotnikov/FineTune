import Foundation

/// A bundle of audio settings applied automatically when a matching game starts.
nonisolated struct GameProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    /// Bundle identifiers (persistence identifiers) of the apps this profile belongs to.
    var bundleIDs: [String]
    /// Also apply to any app whose bundle declares the Games category and has no explicit profile.
    var appliesToDetectedGames: Bool
    /// Re-apply on every launch. When false, the profile only applies when you press "Apply now".
    var autoApply: Bool
    /// nil = leave the app's own EQ untouched.
    var eq: EQSettings?
    /// nil = leave the app's own dynamics/spatial untouched.
    var dsp: ChannelDSPSettings?

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, bundleIDs: [String] = [],
         appliesToDetectedGames: Bool = false, autoApply: Bool = true,
         eq: EQSettings? = nil, dsp: ChannelDSPSettings? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.bundleIDs = bundleIDs
        self.appliesToDetectedGames = appliesToDetectedGames
        self.autoApply = autoApply
        self.eq = eq
        self.dsp = dsp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Profile",
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            bundleIDs: try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? [],
            appliesToDetectedGames: try c.decodeIfPresent(Bool.self, forKey: .appliesToDetectedGames) ?? false,
            autoApply: try c.decodeIfPresent(Bool.self, forKey: .autoApply) ?? true,
            eq: try c.decodeIfPresent(EQSettings.self, forKey: .eq),
            dsp: try c.decodeIfPresent(ChannelDSPSettings.self, forKey: .dsp)
        )
    }
}

/// Ready-made starting points for new profiles.
nonisolated enum GameProfileTemplate: String, CaseIterable, Identifiable {
    case blank, competitiveFPS, cinematic, voiceChat, nightMode

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blank: return "Blank"
        case .competitiveFPS: return "Competitive FPS"
        case .cinematic: return "Cinematic"
        case .voiceChat: return "Voice Chat"
        case .nightMode: return "Night Mode"
        }
    }

    func makeProfile() -> GameProfile {
        var profile = GameProfile(name: name)
        switch self {
        case .blank:
            break
        case .competitiveFPS:
            profile.eq = EQPreset.competitivePro.settings
            var dsp = ChannelDSPSettings()
            dsp.dynamics = DynamicsPreset.limiterOnly.settings
            profile.dsp = dsp
        case .cinematic:
            profile.eq = EQPreset.cinematicPro.settings
            var dsp = ChannelDSPSettings()
            dsp.spatial = SpatialPreset.virtualSurround.settings
            dsp.dynamics = DynamicsPreset.gentleLeveler.settings
            profile.dsp = dsp
        case .voiceChat:
            profile.eq = EQPreset.voiceChatPro.settings
            var dsp = ChannelDSPSettings()
            dsp.dynamics = DynamicsPreset.voiceLeveler.settings
            profile.dsp = dsp
        case .nightMode:
            profile.eq = EQPreset.gunfireTamer.settings
            var dsp = ChannelDSPSettings()
            dsp.dynamics = DynamicsPreset.gameNight.settings
            profile.dsp = dsp
        }
        return profile
    }
}

/// Pure matching rules, kept separate from the engine so they are easy to test.
nonisolated enum GameProfileMatcher {
    /// Picks the profile for an app: an explicit bundle match wins; otherwise the first
    /// enabled "detected games" profile if the app is a game. Disabled profiles never match.
    static func profile(for bundleID: String, isDetectedGame: Bool, in profiles: [GameProfile]) -> GameProfile? {
        if let explicit = profiles.first(where: { $0.isEnabled && $0.bundleIDs.contains(bundleID) }) {
            return explicit
        }
        guard isDetectedGame else { return nil }
        return profiles.first { $0.isEnabled && $0.appliesToDetectedGames }
    }
}
