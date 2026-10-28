import Foundation

/// Persisted per-tab audio state, keyed by the tab's hostname so it survives
/// browser restarts (Chromium tab IDs do not).
nonisolated struct BrowserTabSettings: Codable, Equatable {
    var volume: Float = 1.0
    var isMuted: Bool = false
    var eq: EQSettings = .flat

    static let `default` = BrowserTabSettings()

    var isDefault: Bool { self == Self.default }

    init(volume: Float = 1.0, isMuted: Bool = false, eq: EQSettings = .flat) {
        self.volume = Self.sanitizedVolume(volume)
        self.isMuted = isMuted
        self.eq = eq
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = Self.sanitizedVolume(try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0)
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        eq = try c.decodeIfPresent(EQSettings.self, forKey: .eq) ?? .flat
    }

    private static func sanitizedVolume(_ value: Float) -> Float {
        value.isFinite ? max(0, min(value, 1.0)) : 1.0
    }
}

/// A live browser tab reported by the companion extension.
nonisolated struct BrowserTab: Identifiable, Equatable {
    let id: Int              // Chromium tab ID, valid for the current browser session
    var title: String
    var host: String         // Persistence key; empty for non-web pages
    var favIconURL: URL?
    var isAudible: Bool
    var settings: BrowserTabSettings

    /// Key under which `settings` is stored; nil for tabs that cannot be persisted.
    var persistenceKey: String? { host.isEmpty ? nil : host }
}
