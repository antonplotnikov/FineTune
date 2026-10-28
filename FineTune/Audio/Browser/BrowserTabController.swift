import Foundation

/// Owns the live browser-tab list and applies per-tab volume/mute/EQ via the extension bridge.
@Observable
@MainActor
final class BrowserTabController {
    private(set) var tabs: [BrowserTab] = []
    private(set) var isExtensionConnected = false

    /// The browser app's own EQ. While any tab has its own EQ, the app-level tap EQ is bypassed
    /// (it would sit on top of the tab's preset), so this curve is applied inside the extension
    /// to the tabs that have no EQ of their own.
    private(set) var baseEQ: EQSettings = .flat
    /// True while at least one tab has an EQ of its own.
    private(set) var hasTabEQ = false
    /// Called when `hasTabEQ` changes, so the engine can bypass/restore the app-level EQ.
    var onTabEQActivityChanged: (() -> Void)?

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
        server.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            isExtensionConnected = connected
            // A fresh connection (e.g. the extension's service worker restarted) has lost its
            // state, so treat every tab as new and push saved settings again.
            if connected { tabs = []; refreshTabEQActivity() }
        }
        server.start()
        self.server = server
    }

    func stop() {
        server?.stop()
        server = nil
        tabs = []
        isExtensionConnected = false
        refreshTabEQActivity()
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

    /// Updates the browser app's EQ that tabs without their own EQ fall back to.
    func setBaseEQ(_ eq: EQSettings) {
        guard eq != baseEQ else { return }
        baseEQ = eq
        if hasTabEQ { pushAll() }
    }

    // MARK: - Private

    private func update(_ tabId: Int, _ change: (inout BrowserTabSettings) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        change(&tabs[index].settings)
        let tab = tabs[index]
        if let key = tab.persistenceKey {
            settingsManager.setBrowserTabSettings(tab.settings, for: key)
        }
        if refreshTabEQActivity() {
            pushAll()
        } else {
            push(tab)
        }
    }

    /// Settings as the extension should render them: a tab without its own EQ plays through the
    /// browser app's EQ while any other tab has a preset (the tap-level EQ is bypassed then).
    private func effectiveSettings(for tab: BrowserTab) -> BrowserTabSettings {
        var settings = tab.settings
        if hasTabEQ && settings.eq.isFlat { settings.eq = baseEQ }
        return settings
    }

    private func push(_ tab: BrowserTab) {
        server?.send(tabId: tab.id, settings: effectiveSettings(for: tab))
    }

    private func pushAll() {
        for tab in tabs where tab.isAudible || !tab.settings.isDefault { push(tab) }
    }

    /// Recomputes `hasTabEQ`; returns true (after notifying the engine) when it changed.
    @discardableResult
    private func refreshTabEQActivity() -> Bool {
        let active = tabs.contains { !$0.settings.eq.isFlat }
        guard active != hasTabEQ else { return false }
        hasTabEQ = active
        onTabEQActivityChanged?()
        return true
    }

    /// Replaces the tab list from an extension report and pushes saved settings to tabs the
    /// extension has not seen yet (e.g. after a browser restart) or whose settings changed
    /// because the tab navigated to another host.
    private func applyReported(_ reported: [BrowserTab]) {
        let previous = Dictionary(tabs.map { ($0.id, $0.settings) }, uniquingKeysWith: { _, last in last })
        tabs = reported
        if refreshTabEQActivity() {
            pushAll()
            return
        }
        for tab in reported {
            if let old = previous[tab.id] {
                if old != tab.settings { push(tab) }
            } else if !tab.settings.isDefault || (hasTabEQ && tab.isAudible) {
                push(tab)
            }
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
