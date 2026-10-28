// FineTune/Views/EQPanelView.swift
import SwiftUI

struct EQPanelView: View {
    @Binding var settings: EQSettings
    let userPresets: [UserEQPreset]
    let onPresetSelected: (EQPreset) -> Void
    let onUserPresetSelected: (UserEQPreset) -> Void
    let onSettingsChanged: (EQSettings) -> Void
    let onSavePreset: (String, EQSettings) -> Void
    let onDeleteUserPreset: (UUID) -> Void
    let onRenameUserPreset: (UUID, String) -> Void

    @State private var history = EQEditHistory()
    @State private var ab = EQABCompare()
    @State private var lastSettings: EQSettings?
    @State private var isApplyingHistory = false

    @State private var isSaving = false
    @State private var savePresetName = ""
    @FocusState private var isSaveFieldFocused: Bool

    @State private var isRenaming = false
    @State private var renamePresetName = ""
    @State private var renamingPresetID: UUID?
    @FocusState private var isRenameFieldFocused: Bool

    private let frequencyLabels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    // MARK: - Preset Matching

    /// Finds the matching built-in preset for the current band gains, if any.
    private var currentBuiltInPreset: EQPreset? {
        EQPreset.allCases.first { $0.settings.hasSameCurve(as: settings) }
    }

    /// Finds the matching user preset for the current band gains, if any.
    private var currentUserPreset: UserEQPreset? {
        userPresets.first { $0.settings.hasSameCurve(as: settings) }
    }

    /// The currently selected picker item (built-in, user, or nil for "Custom").
    private var selectedPickerItem: EQPickerItem? {
        if let builtIn = currentBuiltInPreset {
            return EQPickerItem(builtIn: builtIn)
        } else if let user = currentUserPreset {
            return EQPickerItem(user: user)
        }
        return nil
    }

    /// Whether the current curve is custom (doesn't match any preset).
    private var isCustomCurve: Bool { selectedPickerItem == nil }

    var body: some View {
        // Entire EQ panel content inside recessed background
        VStack(spacing: 12) {
            // Header: Toggle left, save field or spacer in middle, Preset right
            HStack {
                // EQ toggle on left
                HStack(spacing: 6) {
                    Toggle("", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .labelsHidden()
                        .frame(width: 30)  // scaleEffect doesn't shrink layout; reserve the visual width
                        .onChange(of: settings.isEnabled) { _, _ in
                            onSettingsChanged(settings)
                        }
                    Text("EQ")
                        .font(DesignTokens.Typography.pickerText)
                        .foregroundStyle(.primary)
                        .fixedSize()
                }

                if isRenaming {
                    renamePresetField
                        .transition(.blurReplace.combined(with: .opacity))
                } else if isSaving {
                    savePresetField
                        .transition(.blurReplace.combined(with: .opacity))
                } else {
                    Spacer()

                    if currentUserPreset != nil {
                        renameButton
                            .transition(.blurReplace.combined(with: .opacity))
                    } else if isCustomCurve {
                        saveButton
                            .transition(.blurReplace.combined(with: .opacity))
                    }
                }

                // Preset picker on right (always visible)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Preset")
                        .font(DesignTokens.Typography.pickerText)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    EQPresetPicker(
                        selectedItem: selectedPickerItem,
                        userPresets: userPresets,
                        onBuiltInSelected: onPresetSelected,
                        onUserPresetSelected: onUserPresetSelected,
                        onDeleteUserPreset: onDeleteUserPreset,
                        onRenameUserPreset: onRenameUserPreset
                    )
                }
            }
            .zIndex(1)  // Ensure dropdown renders above sliders

            // Mode switch on its own row so the header never reflows when the
            // save/rename field appears.
            HStack {
                Picker("", selection: Binding(
                    get: { settings.mode },
                    set: { newMode in
                        settings.switchMode(to: newMode)
                        onSettingsChanged(settings)
                    }
                )) {
                    ForEach(EQSettings.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 180)
                .help("Graphic: 10 fixed sliders. Parametric: free frequency, gain, Q and filter type.")
                Spacer()
                editTools
            }
            .opacity(settings.isEnabled ? 1.0 : 0.5)

            if settings.mode == .parametric {
                ParametricEQView(settings: $settings, onSettingsChanged: onSettingsChanged)
                    .opacity(settings.isEnabled ? 1.0 : 0.3)
                    .allowsHitTesting(settings.isEnabled)
            } else {
                EQResponseGraphView(settings: settings)
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { index in
                        EQSliderView(
                            frequency: frequencyLabels[index],
                            gain: Binding(
                                get: { settings.bandGains[index] },
                                set: { newValue in
                                    settings.bandGains[index] = newValue
                                    onSettingsChanged(settings)
                                }
                            )
                        )
                        .frame(width: 26, height: 100)
                        .frame(maxWidth: .infinity)
                    }
                }
                .opacity(settings.isEnabled ? 1.0 : 0.3)
                .allowsHitTesting(settings.isEnabled)
                .animation(.easeInOut(duration: 0.2), value: settings.isEnabled)
            }

            preampRow
                .opacity(settings.isEnabled ? 1.0 : 0.3)
                .allowsHitTesting(settings.isEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignTokens.Colors.recessedBackground)
        }
        .padding(.horizontal, 2)
        .padding(.top, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .animation(DesignTokens.Animation.quick, value: isSaving)
        .animation(DesignTokens.Animation.quick, value: isRenaming)
        .onAppear { lastSettings = settings }
        .onChange(of: settings) { _, newValue in
            defer { lastSettings = newValue }
            if isApplyingHistory { isApplyingHistory = false; return }
            if let previous = lastSettings, previous != newValue { history.record(previous: previous) }
            ab.store(current: newValue)
        }
    }

    // MARK: - Edit tools (undo / redo / A-B / copy / paste)

    private func apply(_ value: EQSettings) {
        // Only arm the suppression flag when the binding will actually change; otherwise
        // onChange never fires and the flag would swallow the next real edit.
        isApplyingHistory = value != settings
        settings = value
        ab.store(current: value)
        onSettingsChanged(value)
    }

    private func toolButton(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(enabled ? DesignTokens.Colors.interactiveDefault : DesignTokens.Colors.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private var editTools: some View {
        HStack(spacing: 10) {
            toolButton("arrow.uturn.backward", help: "Undo", enabled: history.canUndo) {
                if let previous = history.undo(current: settings) { apply(previous) }
            }
            toolButton("arrow.uturn.forward", help: "Redo", enabled: history.canRedo) {
                if let next = history.redo(current: settings) { apply(next) }
            }

            Button {
                if ab.isActive { apply(ab.toggle(current: settings)) } else { ab.begin(current: settings) }
            } label: {
                Text(ab.isActive ? "Editing \(ab.activeSlot.rawValue)" : "A/B")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(ab.isActive ? Color.white : DesignTokens.Colors.interactiveDefault)
                    .background(Capsule().fill(ab.isActive ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.sliderTrack))
            }
            .buttonStyle(.plain)
            .help(ab.isActive ? "Switch between your original (A) and edited (B) curve" : "Compare: keep this curve as A and edit B")
            if ab.isActive {
                toolButton("xmark.circle", help: "Finish comparing") { ab.end() }
            }

            toolButton("doc.on.doc", help: "Copy this curve") {
                if let text = settings.clipboardString {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            toolButton("doc.on.clipboard", help: "Paste a copied curve") {
                if let text = NSPasteboard.general.string(forType: .string),
                   let pasted = EQSettings.fromClipboard(text) {
                    apply(settings.applyingCurve(from: pasted))
                }
            }
        }
    }

    // MARK: - Preamp

    /// Output gain for the whole curve, with one-click headroom so boosted curves don't clip.
    private var preampRow: some View {
        let peak = BiquadMath.peakBoostDB(for: settings)
        let headroomShort = Double(settings.preampDB) + peak > 0.05
        return HStack(spacing: DesignTokens.Spacing.sm) {
            Text("Preamp")
                .font(DesignTokens.Typography.pickerText)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            LiquidGlassSlider(
                value: Binding(
                    get: { Double(settings.preampDB) },
                    set: { newValue in
                        settings.preampDB = EQSettings.clampPreamp(Float((newValue * 10).rounded() / 10))
                        onSettingsChanged(settings)
                    }
                ),
                in: Double(EQSettings.minPreampDB)...Double(EQSettings.maxPreampDB),
                showUnityMarker: false
            )
            .frame(maxWidth: 220)

            EQNumberField(
                label: "dB",
                value: Binding(
                    get: { Double(settings.preampDB) },
                    set: { settings.preampDB = EQSettings.clampPreamp(Float($0)); onSettingsChanged(settings) }
                ),
                range: Double(EQSettings.minPreampDB)...Double(EQSettings.maxPreampDB),
                decimals: 1
            )

            Button {
                settings.preampDB = BiquadMath.autoPreampDB(for: settings)
                onSettingsChanged(settings)
            } label: {
                Text("Auto")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.interactiveDefault)
            }
            .buttonStyle(.plain)
            .help("Set preamp to cancel the curve's loudest boost (\(String(format: "%+.1f", peak)) dB)")

            if headroomShort {
                Label("May clip", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.orange)
                    .help("The curve boosts up to \(String(format: "%+.1f", peak)) dB; lower the preamp or press Auto.")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            savePresetName = ""
            isSaving = true
            Task { @MainActor in
                isSaveFieldFocused = true
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Colors.interactiveDefault)
        }
        .buttonStyle(.plain)
        .help("Save current EQ as preset")
        .accessibilityLabel("Save current EQ curve as a new preset")
    }

    // MARK: - Save Preset Field

    private var savePresetField: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            TextField("Preset name", text: $savePresetName)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .focused($isSaveFieldFocused)
                .onSubmit { commitSave() }
                .onExitCommand { cancelSave() }

            Button {
                commitSave()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        savePresetName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.accentPrimary
                    )
            }
            .buttonStyle(.plain)
            .disabled(savePresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Save preset")
            .accessibilityLabel("Confirm save preset")

            Button {
                cancelSave()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .accessibilityLabel("Cancel saving preset")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                .strokeBorder(DesignTokens.Colors.menuBorderHover, lineWidth: 0.5)
        }
    }

    // MARK: - Save Actions

    private func commitSave() {
        let trimmed = savePresetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Store with isEnabled = true — isEnabled is per-app state, not preset state
        var presetSettings = settings
        presetSettings.isEnabled = true
        onSavePreset(trimmed, presetSettings)
        isSaving = false
        savePresetName = ""
    }

    private func cancelSave() {
        isSaving = false
        savePresetName = ""
    }

    // MARK: - Rename Button

    private var renameButton: some View {
        Button {
            if let preset = currentUserPreset {
                renamingPresetID = preset.id
                renamePresetName = preset.name
                isRenaming = true
                Task { @MainActor in
                    isRenameFieldFocused = true
                }
            }
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 12))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Colors.interactiveDefault)
        }
        .buttonStyle(.plain)
        .help("Rename preset")
        .accessibilityLabel("Rename current preset")
    }

    // MARK: - Rename Preset Field

    private var renamePresetField: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            TextField("Preset name", text: $renamePresetName)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .focused($isRenameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { cancelRename() }

            Button {
                commitRename()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        renamePresetName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.accentPrimary
                    )
            }
            .buttonStyle(.plain)
            .disabled(renamePresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Confirm rename")
            .accessibilityLabel("Confirm rename preset")

            Button {
                cancelRename()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .accessibilityLabel("Cancel renaming preset")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                .strokeBorder(DesignTokens.Colors.menuBorderHover, lineWidth: 0.5)
        }
    }

    // MARK: - Rename Actions

    private func commitRename() {
        let trimmed = renamePresetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let id = renamingPresetID else { return }
        onRenameUserPreset(id, trimmed)
        isRenaming = false
        renamePresetName = ""
        renamingPresetID = nil
    }

    private func cancelRename() {
        isRenaming = false
        renamePresetName = ""
        renamingPresetID = nil
    }
}

// MARK: - Previews

#Preview {
    // Simulating how it appears inside ExpandableGlassRow
    VStack {
        EQPanelView(
            settings: .constant(EQSettings()),
            userPresets: [
                UserEQPreset(name: "My Bass", settings: EQSettings(bandGains: [6, 5, 4, 0, 0, 0, 0, 0, 0, 0]))
            ],
            onPresetSelected: { _ in },
            onUserPresetSelected: { _ in },
            onSettingsChanged: { _ in },
            onSavePreset: { _, _ in },
            onDeleteUserPreset: { _ in },
            onRenameUserPreset: { _, _ in }
        )
    }
    .padding(.horizontal, DesignTokens.Spacing.sm)
    .padding(.vertical, DesignTokens.Spacing.xs)
    .frame(width: 550)
    .padding()
    .background(Color.black.opacity(0.4))
}

#Preview("Custom Curve - Save Visible") {
    VStack {
        EQPanelView(
            settings: .constant(EQSettings(bandGains: [3, 2, 1, 0, -1, 0, 2, 3, 1, 0])),
            userPresets: [],
            onPresetSelected: { _ in },
            onUserPresetSelected: { _ in },
            onSettingsChanged: { _ in },
            onSavePreset: { _, _ in },
            onDeleteUserPreset: { _ in },
            onRenameUserPreset: { _, _ in }
        )
    }
    .padding(.horizontal, DesignTokens.Spacing.sm)
    .padding(.vertical, DesignTokens.Spacing.xs)
    .frame(width: 550)
    .padding()
    .background(Color.black)
}
