import Foundation

/// Owns the live browser-tab list and applies per-tab volume/mute/EQ via the extension bridge.
@Observable
@MainActor
final class BrowserTabController {
    private(set) var tabs: [BrowserTab] = []
    private(set) var isExtensionConnected = false

    private let settingsManager: SettingsManager
    private var server: BrowserBridgeServer?

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    func start() {
        guard server == nil else { return }
        let manager = settingsManager
        let server = BrowserBridgeServer(
            tokenProvider: { manager.browserBridgeToken() },
            settingsLookup: { manager.getBrowserTabSettings(for: $0) }
        )
        server.onTabsChanged = { [weak self] tabs in self?.applyReported(tabs) }
        server.onConnectionChanged = { [weak self] connected in self?.isExtensionConnected = connected }
        server.start()
        self.server = server
    }

    func stop() {
        server?.stop()
        server = nil
        tabs = []
        isExtensionConnected = false
    }

    var bridgeToken: String { settingsManager.browserBridgeToken() }

    func tabs(withAudioOnly audibleOnly: Bool) -> [BrowserTab] {
        audibleOnly ? tabs.filter { $0.isAudible || !$0.settings.isDefault } : tabs
    }

    // MARK: - Mutations

    func setVolume(_ volume: Float, for tabId: Int) {
        update(tabId) { $0.volume = volume.isFinite ? max(0, min(volume, 1)) : 1 }
    }

    func setMuted(_ muted: Bool, for tabId: Int) {
        update(tabId) { $0.isMuted = muted }
    }

    func setEQ(_ eq: EQSettings, for tabId: Int) {
        update(tabId) { $0.eq = eq }
    }

    // MARK: - Private

    private func update(_ tabId: Int, _ change: (inout BrowserTabSettings) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        change(&tabs[index].settings)
        let tab = tabs[index]
        if let key = tab.persistenceKey {
            settingsManager.setBrowserTabSettings(tab.settings, for: key)
        }
        server?.send(tabId: tab.id, settings: tab.settings)
    }

    /// Replaces the tab list from an extension report and pushes saved settings to tabs
    /// that have non-default state (e.g. after a browser restart).
    private func applyReported(_ reported: [BrowserTab]) {
        let known = Set(tabs.map(\.id))
        tabs = reported
        for tab in reported where !known.contains(tab.id) && !tab.settings.isDefault {
            server?.send(tabId: tab.id, settings: tab.settings)
        }
    }
}

extension BrowserTabController {
    /// Bundle ID prefixes of Chromium-based browsers the extension can run in.
    private static let chromiumBundlePrefixes = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static func isChromiumBrowser(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return chromiumBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }
}
