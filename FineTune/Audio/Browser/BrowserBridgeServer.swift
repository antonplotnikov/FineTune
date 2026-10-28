import Foundation
import Network
import os

/// Wire protocol shared with `BrowserExtension/`. All messages are JSON text frames.
///
/// Extension → app:
///   `{"type":"hello","token":"…","browser":"com.google.Chrome"}`  (must be first)
///   `{"type":"tabs","tabs":[{"id":1,"title":"…","host":"…","favIconUrl":"…","audible":true}]}`
/// App → extension:
///   `{"type":"set","tabId":1,"volume":0.5,"muted":false,"eq":[0,0,…10 gains…]}`
nonisolated enum BrowserBridgeMessage {
    struct Hello: Decodable { let token: String; let browser: String? }

    struct TabInfo: Decodable {
        let id: Int
        let title: String?
        let host: String?
        let favIconUrl: String?
        let audible: Bool?
    }

    struct Envelope: Decodable {
        let type: String
        let token: String?
        let browser: String?
        let tabs: [TabInfo]?
    }

    static func decode(_ data: Data) -> Envelope? {
        try? JSONDecoder().decode(Envelope.self, from: data)
    }

    /// Full per-band filter description (always `EQSettings.bandCount` entries) so the
    /// extension can mirror both graphic and parametric curves.
    static func bandPayload(for eq: EQSettings) -> [[String: Any]] {
        let neutral: [String: Any] = ["type": "peaking", "frequency": 1000.0, "gain": 0.0, "q": ParametricBand.defaultQ, "enabled": false]
        guard eq.isEnabled else { return Array(repeating: neutral, count: EQSettings.bandCount) }
        var bands: [[String: Any]]
        switch eq.mode {
        case .graphic:
            let gains = eq.clampedGains
            bands = EQSettings.frequencies.enumerated().map { index, frequency in
                ["type": "peaking", "frequency": frequency, "gain": Double(gains[index]),
                 "q": BiquadMath.graphicEQQ, "enabled": true]
            }
        case .parametric:
            bands = eq.clampedParametricBands.map { band in
                ["type": band.type.webAudioType, "frequency": band.frequency, "gain": Double(band.gainDB),
                 "q": band.q, "enabled": band.isEnabled]
            }
        }
        while bands.count < EQSettings.bandCount { bands.append(neutral) }
        return bands
    }

    static func encodeSet(tabId: Int, settings: BrowserTabSettings) -> Data? {
        let eq = settings.eq.isEnabled ? settings.eq.clampedGains : Array(repeating: Float(0), count: EQSettings.bandCount)
        let payload: [String: Any] = [
            "type": "set",
            "tabId": tabId,
            "volume": settings.volume,
            "muted": settings.isMuted,
            "eq": eq,
            "bands": bandPayload(for: settings.eq),
            "preamp": settings.eq.isEnabled ? Double(EQSettings.clampPreamp(settings.eq.preampDB)) : 0.0,
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}

/// Loopback-only WebSocket server the companion browser extension connects to.
@MainActor
final class BrowserBridgeServer {
    nonisolated static let defaultPort: UInt16 = 48731

    /// Called with the full tab list each time an authenticated extension reports.
    var onTabsChanged: (([BrowserTab]) -> Void)?
    /// Called when the extension connection state changes.
    var onConnectionChanged: ((Bool) -> Void)?

    private(set) var isConnected = false

    private let port: UInt16
    private let tokenProvider: () -> String
    private let settingsLookup: (String) -> BrowserTabSettings
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FineTune", category: "BrowserBridge")

    private var listener: NWListener?
    private var connection: NWConnection?
    private var authenticated = false

    init(port: UInt16 = BrowserBridgeServer.defaultPort,
         tokenProvider: @escaping () -> String,
         settingsLookup: @escaping (String) -> BrowserTabSettings) {
        self.port = port
        self.tokenProvider = tokenProvider
        self.settingsLookup = settingsLookup
    }

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        // Bind to loopback only so the bridge is never reachable from the network.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.logger.error("Bridge listener failed: \(error.localizedDescription)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            logger.error("Could not start bridge listener: \(error.localizedDescription)")
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        setConnected(false)
    }

    /// Pushes a tab's settings to the extension. No-op while disconnected.
    func send(tabId: Int, settings: BrowserTabSettings) {
        guard authenticated, let connection,
              let data = BrowserBridgeMessage.encodeSet(tabId: tabId, settings: settings) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "set", metadata: [meta])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        // A single extension instance is expected; a newer connection replaces the old one.
        connection?.cancel()
        connection = conn
        authenticated = false
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            Task { @MainActor in
                guard let self, let conn, self.connection === conn else { return }
                switch state {
                case .failed, .cancelled:
                    self.connection = nil
                    self.authenticated = false
                    self.setConnected(false)
                    self.onTabsChanged?([])
                default: break
                }
            }
        }
        conn.start(queue: .main)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self, weak conn] data, _, _, error in
            Task { @MainActor in
                guard let self, let conn, self.connection === conn else { return }
                if let data, !data.isEmpty { self.handle(data, on: conn) }
                if error == nil { self.receive(on: conn) } else { conn.cancel() }
            }
        }
    }

    private func handle(_ data: Data, on conn: NWConnection) {
        guard let message = BrowserBridgeMessage.decode(data) else { return }
        if !authenticated {
            guard message.type == "hello", message.token == tokenProvider() else {
                logger.warning("Rejected bridge connection with bad hello")
                conn.cancel()
                return
            }
            authenticated = true
            setConnected(true)
            return
        }
        guard message.type == "tabs", let infos = message.tabs else { return }
        let tabs = infos.map { info -> BrowserTab in
            let host = info.host ?? ""
            return BrowserTab(
                id: info.id,
                title: info.title ?? host,
                host: host,
                favIconURL: info.favIconUrl.flatMap(URL.init(string:)),
                isAudible: info.audible ?? false,
                settings: host.isEmpty ? .default : settingsLookup(host)
            )
        }
        onTabsChanged?(tabs)
    }

    private func setConnected(_ value: Bool) {
        guard isConnected != value else { return }
        isConnected = value
        onConnectionChanged?(value)
    }
}
