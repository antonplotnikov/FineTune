// FineTune/Views/Settings/Tabs/GamesTab.swift
import AppKit
import SwiftUI

/// Game profiles: bundles of EQ + dynamics + spatial settings applied automatically when a game starts.
@MainActor
struct GamesTab: View {
    @Bindable var settings: SettingsManager
    @Bindable var audioEngine: AudioEngine

    @State private var selectedID: UUID?
    @State private var status: String?

    private var profiles: [GameProfile] { settings.gameProfiles }

    private var selectedProfile: GameProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
                .frame(width: 190)
            Divider()
            ScrollView {
                if let profile = selectedProfile {
                    editor(for: profile)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    emptyState
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { selectedProfile?.id }, set: { selectedID = $0 })) {
                ForEach(profiles) { profile in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(profile.isEnabled ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(profile.name).lineLimit(1)
                    }
                    .tag(profile.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            Menu {
                ForEach(GameProfileTemplate.allCases) { template in
                    Button(template.name) {
                        let profile = template.makeProfile()
                        settings.addGameProfile(profile)
                        selectedID = profile.id
                    }
                }
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .padding(10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("No game profiles yet").font(.system(size: 15, weight: .semibold))
            Text("A profile bundles an EQ curve, compressor/limiter and spatial settings and applies them automatically when your game starts. Create one from a template with “New Profile”.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Editor

    private func binding(for profile: GameProfile) -> Binding<GameProfile> {
        Binding(
            get: { settings.gameProfiles.first { $0.id == profile.id } ?? profile },
            set: { settings.updateGameProfile($0) }
        )
    }

    private func editor(for profile: GameProfile) -> some View {
        let p = binding(for: profile)
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                TextField("Profile name", text: p.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold))
                Toggle("Enabled", isOn: p.isEnabled).toggleStyle(.switch).controlSize(.small)
            }

            SettingsSection("When to apply") {
                SettingsRow("Apply automatically", description: "Each time a covered app starts producing audio. Off = only when you press “Apply now”.") {
                    Toggle("", isOn: p.autoApply).toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
                SettingsRowDivider()
                SettingsRow("Use for detected games", description: "Also covers any app that declares itself a game (App Store category Games) and has no profile of its own.") {
                    Toggle("", isOn: p.appliesToDetectedGames).toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }

            appsSection(p)
            soundSection(p)
            actionsSection(p)

            if let status {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Apps

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    /// Running regular apps plus anything currently making sound, minus apps already in the profile.
    private func addableApps(excluding existing: [String]) -> [(id: String, name: String)] {
        var seen = Set(existing)
        var result: [(String, String)] = []
        for app in audioEngine.apps {
            let id = app.persistenceIdentifier
            if seen.insert(id).inserted { result.append((id, app.name)) }
        }
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            guard let id = running.bundleIdentifier, seen.insert(id).inserted else { continue }
            result.append((id, running.localizedName ?? id))
        }
        return result.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func appsSection(_ p: Binding<GameProfile>) -> some View {
        SettingsSection("Apps") {
            if p.wrappedValue.bundleIDs.isEmpty {
                SettingsRow("No apps added", description: "Add your game, or rely on “Use for detected games”.") { EmptyView() }
            }
            ForEach(Array(p.wrappedValue.bundleIDs.enumerated()), id: \.element) { index, bundleID in
                if index > 0 { SettingsRowDivider() }
                SettingsRow(appName(for: bundleID), description: bundleID) {
                    Button {
                        p.wrappedValue.bundleIDs.removeAll { $0 == bundleID }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                }
            }
            SettingsRowDivider()
            SettingsRow("Add app", description: "Pick from running apps (launch the game first).") {
                Menu("Choose…") {
                    let options = addableApps(excluding: p.wrappedValue.bundleIDs)
                    if options.isEmpty { Text("No running apps found") }
                    ForEach(options, id: \.id) { option in
                        Button(option.name) { p.wrappedValue.bundleIDs.append(option.id) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    // MARK: Sound

    private func eqSummary(_ eq: EQSettings?) -> String {
        guard let eq else { return "Don't change" }
        if let preset = EQPreset.allCases.first(where: { $0.settings.hasSameCurve(as: eq) }) { return preset.name }
        return eq.mode == .parametric ? "Custom parametric" : "Custom curve"
    }

    private func soundSection(_ p: Binding<GameProfile>) -> some View {
        let dsp = p.wrappedValue.dsp
        return SettingsSection("Sound") {
            SettingsRow("Equalizer", description: "The EQ curve set on the app.") {
                Menu(eqSummary(p.wrappedValue.eq)) {
                    Button("Don't change") { p.wrappedValue.eq = nil }
                    Divider()
                    ForEach(EQPreset.Category.allCases) { category in
                        Menu(category.rawValue) {
                            ForEach(EQPreset.presets(for: category)) { preset in
                                Button(preset.name) { p.wrappedValue.eq = preset.settings }
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            SettingsRowDivider()
            SettingsRow("Dynamics", description: "Compressor and limiter.") {
                Menu(dsp.map { d in DynamicsPreset.allCases.first { $0.settings == d.dynamics }?.name ?? "Custom" } ?? "Don't change") {
                    Button("Don't change") { p.wrappedValue.dsp = nil }
                    Divider()
                    ForEach(DynamicsPreset.allCases) { preset in
                        Button(preset.name) {
                            var d = p.wrappedValue.dsp ?? ChannelDSPSettings()
                            d.dynamics = preset.settings
                            p.wrappedValue.dsp = d
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            SettingsRowDivider()
            SettingsRow("Spatial", description: "Stereo width, crossfeed and room.") {
                Menu(dsp.map { d in SpatialPreset.allCases.first { $0.settings == d.spatial }?.name ?? "Custom" } ?? "Don't change") {
                    Button("Don't change") { p.wrappedValue.dsp = nil }
                    Divider()
                    ForEach(SpatialPreset.allCases) { preset in
                        Button(preset.name) {
                            var d = p.wrappedValue.dsp ?? ChannelDSPSettings()
                            d.spatial = preset.settings
                            p.wrappedValue.dsp = d
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    // MARK: Actions

    private func actionsSection(_ p: Binding<GameProfile>) -> some View {
        SettingsSection("Actions") {
            SettingsRow("Capture from a running app", description: "Copy that app’s current EQ, dynamics and spatial settings into this profile.") {
                Menu("Choose…") {
                    if audioEngine.apps.isEmpty { Text("No apps are playing audio") }
                    ForEach(audioEngine.apps) { app in
                        Button(app.name) {
                            let captured = audioEngine.captureProfileSettings(from: app)
                            p.wrappedValue.eq = captured.eq
                            p.wrappedValue.dsp = captured.dsp
                            status = "Captured settings from \(app.name)."
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            SettingsRowDivider()
            SettingsRow("Apply now", description: "Apply this profile to matching apps that are running right now.") {
                Button("Apply") {
                    let count = audioEngine.applyGameProfileToRunningApps(p.wrappedValue)
                    status = count == 0 ? "No matching app is running." : "Applied to \(count) app\(count == 1 ? "" : "s")."
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            SettingsRowDivider()
            SettingsRow("Delete profile") {
                Button("Delete", role: .destructive) {
                    let id = p.wrappedValue.id
                    selectedID = nil
                    settings.deleteGameProfile(id: id)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}
