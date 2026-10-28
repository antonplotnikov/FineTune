// FineTune/Views/Settings/Tabs/BrowserSettingsTab.swift
import AppKit
import SwiftUI

/// Setup and status for the Chromium companion extension (per-tab audio control).
@MainActor
struct BrowserSettingsTab: View {
    let controller: BrowserTabController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection("Per-Tab Audio") {
                    SettingsRow(
                        "Extension status",
                        description: controller.isExtensionConnected
                            ? "Connected. Tabs appear under your browser in the menu bar."
                            : "Not connected. Install the extension and paste the token below."
                    ) {
                        Circle()
                            .fill(controller.isExtensionConnected ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        "Token",
                        description: "Paste into the extension popup. Port \(BrowserBridgeServer.defaultPort)."
                    ) {
                        Button("Copy Token") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(controller.bridgeToken, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        "Install",
                        description: "Chrome, Brave or Edge: open chrome://extensions, enable Developer mode, then Load unpacked and choose the BrowserExtension folder."
                    ) {
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}
