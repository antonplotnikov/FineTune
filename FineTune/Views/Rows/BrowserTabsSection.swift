// FineTune/Views/Rows/BrowserTabsSection.swift
import SwiftUI

/// Collapsible per-tab controls shown under a Chromium browser's app row.
/// Data comes from the companion extension via `BrowserTabController`.
struct BrowserTabsSection: View {
    let controller: BrowserTabController
    let userPresets: [UserEQPreset]
    let onSavePreset: (String, EQSettings) -> Void
    let onDeleteUserPreset: (UUID) -> Void
    let onRenameUserPreset: (UUID, String) -> Void

    @State private var isCollapsed = false
    @State private var eqTabID: Int?

    private var visibleTabs: [BrowserTab] { controller.tabs(withAudioOnly: true) }

    var body: some View {
        if controller.isExtensionConnected, !visibleTabs.isEmpty {
            VStack(spacing: 2) {
                Button {
                    withAnimation(DesignTokens.Animation.quick) { isCollapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Tabs (\(visibleTabs.count))")
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isCollapsed {
                    ForEach(visibleTabs) { tab in
                        tabRow(tab)
                    }
                }
            }
            .padding(.leading, DesignTokens.Spacing.md)
        }
    }

    @ViewBuilder
    private func tabRow(_ tab: BrowserTab) -> some View {
        ExpandableGlassRow(isExpanded: eqTabID == tab.id) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: tab.isAudible ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(width: 14)

                Text(tab.title)
                    .font(DesignTokens.Typography.rowName)
                    .lineLimit(1)
                    .help(tab.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LiquidGlassSlider(
                    value: Binding(
                        get: { Double(tab.settings.volume) },
                        set: { controller.setVolume(Float($0), for: tab.id) }
                    )
                )
                .frame(width: 90)

                MuteButton(isMuted: tab.settings.isMuted || tab.settings.volume == 0) {
                    controller.setMuted(!tab.settings.isMuted, for: tab.id)
                }

                Button {
                    withAnimation(DesignTokens.Animation.quick) {
                        eqTabID = (eqTabID == tab.id) ? nil : tab.id
                    }
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 11))
                        .foregroundStyle(tab.settings.eq == .flat
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.accentPrimary)
                }
                .buttonStyle(.plain)
                .help("Equalizer for this tab")
            }
            .frame(height: DesignTokens.Dimensions.rowContentHeight)
        } expandedContent: {
            EQPanelView(
                settings: Binding(
                    get: { tab.settings.eq },
                    set: { controller.setEQ($0, for: tab.id) }
                ),
                userPresets: userPresets,
                onPresetSelected: { controller.setEQ($0.settings, for: tab.id) },
                onUserPresetSelected: { preset in
                    controller.setEQ(tab.settings.eq.applyingCurve(from: preset.settings), for: tab.id)
                },
                onSettingsChanged: { controller.setEQ($0, for: tab.id) },
                onSavePreset: onSavePreset,
                onDeleteUserPreset: onDeleteUserPreset,
                onRenameUserPreset: onRenameUserPreset
            )
            .padding(.top, DesignTokens.Spacing.sm)
        }
    }
}
