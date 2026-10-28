// FineTuneTests/BrowserBridgeTests.swift
// Tests for the browser-extension bridge protocol and per-tab settings persistence.

import Testing
import Foundation
@testable import FineTune

@Suite("BrowserBridgeMessage — protocol")
struct BrowserBridgeMessageTests {

    @Test("Decodes hello envelope")
    func decodesHello() throws {
        let data = Data(#"{"type":"hello","token":"abc","browser":"chrome"}"#.utf8)
        let msg = try #require(BrowserBridgeMessage.decode(data))
        #expect(msg.type == "hello")
        #expect(msg.token == "abc")
    }

    @Test("Decodes tabs report with optional fields missing")
    func decodesTabs() throws {
        let data = Data(#"{"type":"tabs","tabs":[{"id":7,"title":"Video","host":"example.com","audible":true},{"id":8}]}"#.utf8)
        let msg = try #require(BrowserBridgeMessage.decode(data))
        let tabs = try #require(msg.tabs)
        #expect(tabs.count == 2)
        #expect(tabs[0].id == 7 && tabs[0].audible == true)
        #expect(tabs[1].host == nil)
    }

    @Test("Rejects malformed JSON")
    func rejectsGarbage() {
        #expect(BrowserBridgeMessage.decode(Data("not json".utf8)) == nil)
    }

    @Test("Encodes set command with ten EQ gains")
    func encodesSet() throws {
        let settings = BrowserTabSettings(volume: 0.5, isMuted: true, eq: EQSettings(bandGains: [3] + Array(repeating: 0, count: 9)))
        let data = try #require(BrowserBridgeMessage.encodeSet(tabId: 4, settings: settings))
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["type"] as? String == "set")
        #expect(obj["tabId"] as? Int == 4)
        #expect(obj["muted"] as? Bool == true)
        #expect((obj["eq"] as? [Double])?.count == 10)
        #expect((obj["eq"] as? [Double])?.first == 3)
    }

    @Test("Disabled EQ is sent as flat")
    func disabledEQIsFlat() throws {
        let eq = EQSettings(bandGains: Array(repeating: 6, count: 10), isEnabled: false)
        let data = try #require(BrowserBridgeMessage.encodeSet(tabId: 1, settings: BrowserTabSettings(eq: eq)))
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((obj["eq"] as? [Double])?.allSatisfy { $0 == 0 } == true)
    }
}

@Suite("BrowserTabSettings")
struct BrowserTabSettingsTests {

    @Test("Volume is clamped and non-finite falls back to unity")
    func sanitizesVolume() {
        #expect(BrowserTabSettings(volume: 5).volume == 1)
        #expect(BrowserTabSettings(volume: -1).volume == 0)
        #expect(BrowserTabSettings(volume: .nan).volume == 1)
    }

    @Test("Default detection")
    func defaultDetection() {
        #expect(BrowserTabSettings().isDefault)
        #expect(!BrowserTabSettings(isMuted: true).isDefault)
    }
}

@Suite("SettingsManager — browser tabs")
@MainActor
struct BrowserTabPersistenceTests {

    private func makeManager() -> SettingsManager {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return SettingsManager(directory: dir)
    }

    @Test("Stores per-host settings and drops them when reset to default")
    func storesAndDrops() {
        let manager = makeManager()
        manager.setBrowserTabSettings(BrowserTabSettings(volume: 0.3), for: "example.com")
        #expect(manager.getBrowserTabSettings(for: "example.com").volume == 0.3)
        manager.setBrowserTabSettings(.default, for: "example.com")
        #expect(manager.getBrowserTabSettings(for: "example.com").isDefault)
    }

    @Test("Bridge token is generated once and stable")
    func tokenStable() {
        let manager = makeManager()
        let first = manager.browserBridgeToken()
        #expect(!first.isEmpty)
        #expect(manager.browserBridgeToken() == first)
    }

    @Test("Settings written by v12 decode with empty browser fields")
    func legacyDecode() throws {
        let data = Data(#"{"version":12}"#.utf8)
        let decoded = try JSONDecoder().decode(SettingsManager.Settings.self, from: data)
        #expect(decoded.browserTabSettings.isEmpty)
        #expect(decoded.browserBridgeToken == nil)
    }

    @Test("Chromium bundle detection")
    func chromiumDetection() {
        #expect(BrowserTabController.isChromiumBrowser(bundleID: "com.google.Chrome"))
        #expect(BrowserTabController.isChromiumBrowser(bundleID: "com.google.Chrome.canary"))
        #expect(!BrowserTabController.isChromiumBrowser(bundleID: "com.apple.Safari"))
        #expect(!BrowserTabController.isChromiumBrowser(bundleID: nil))
    }
}
