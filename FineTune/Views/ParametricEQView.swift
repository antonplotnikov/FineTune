// FineTune/Views/ParametricEQView.swift
import SwiftUI

/// Sonar-style parametric editor: response graph with draggable nodes plus exact
/// type / frequency / gain / Q entry for the selected band.
struct ParametricEQView: View {
    @Binding var settings: EQSettings
    let onSettingsChanged: (EQSettings) -> Void

    @Environment(\.eqSpectrumSource) private var spectrumSource
    @AppStorage("eqAnalyzerEnabled") private var analyzerEnabled = true
    @State private var selectedID: UUID?

    private let graphHeight: CGFloat = 130
    private let g = EQGraphDrawing()

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return settings.parametricBands.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 8) {
            graph
            bandStrip
            if let index = selectedIndex {
                bandEditor(index: index)
            } else {
                Text("Select a band, or add one with +")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(height: 28)
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = settings.parametricBands.first?.id }
            spectrumSource?.setActive(analyzerEnabled)
        }
        .onDisappear { spectrumSource?.setActive(false) }
        .onChange(of: analyzerEnabled) { _, on in spectrumSource?.setActive(on) }
    }

    // MARK: - Graph

    private var graph: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Static layer: grid. Live layer: spectrum + response curve (30 fps while analyzing).
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(analyzerEnabled && spectrumSource != nil))) { _ in
                    Canvas { ctx, size in
                        g.drawGrid(ctx, size: size)
                        if analyzerEnabled, let db = spectrumSource?.frame() { g.drawSpectrum(ctx, size: size, db: db) }
                        g.drawCurve(ctx, size: size, settings: settings)
                    }
                }
                // Double-click empty space to add a band right there.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { value in
                        addBand(atX: value.location.x, y: value.location.y, size: size)
                    })
                ForEach(settings.parametricBands) { band in
                    node(for: band, size: size)
                }
            }
            .coordinateSpace(name: "pgraph")
        }
        .frame(height: graphHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Mouse wheel over the graph adjusts the selected band's Q.
        .scrollWheelStep(qScrollBinding, in: ParametricBand.minQ...ParametricBand.maxQ)
        .opacity(settings.isEnabled ? 1 : 0.3)
        .allowsHitTesting(settings.isEnabled)
    }

    private var qScrollBinding: Binding<Double> {
        Binding(
            get: { selectedIndex.map { settings.parametricBands[$0].q } ?? ParametricBand.defaultQ },
            set: { newValue in if let id = selectedID { update(id) { $0.q = newValue } } }
        )
    }

    private func node(for band: ParametricBand, size: CGSize) -> some View {
        let isSelected = band.id == selectedID
        let level = band.type.usesGain ? Double(band.gainDB) : 0
        return Circle()
            .fill(isSelected ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.thumbBackground)
            .overlay(Circle().strokeBorder(DesignTokens.Colors.accentPrimary, lineWidth: 1.5))
            .frame(width: isSelected ? 13 : 10, height: isSelected ? 13 : 10)
            .padding(6)  // larger hit target than the dot itself
            .contentShape(Circle())
            .opacity(band.isEnabled ? 1 : 0.35)
            .position(x: g.x(for: band.frequency, width: size.width), y: g.y(for: level, height: size.height))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("pgraph"))
                    .onChanged { value in
                        selectedID = band.id
                        // Shift: gain only (lock frequency). Option: frequency only (lock gain).
                        let mods = NSEvent.modifierFlags
                        let lockFrequency = mods.contains(.shift)
                        let lockGain = mods.contains(.option)
                        update(band.id) {
                            if !lockFrequency {
                                $0.frequency = ParametricBand.clampFrequency(g.frequency(forX: value.location.x, width: size.width))
                            }
                            if $0.type.usesGain && !lockGain {
                                let raw = g.gain(forY: value.location.y, height: size.height)
                                $0.gainDB = ParametricBand.clampGain((raw / EQSettings.gainStepDB).rounded() * EQSettings.gainStepDB)
                            }
                        }
                    }
            )
            .contextMenu {
                Menu("Filter Type") {
                    ForEach(EQFilterType.allCases) { type in
                        Button(type.title) { update(band.id) { $0.type = type } }
                    }
                }
                Button(band.isEnabled ? "Disable Band" : "Enable Band") { update(band.id) { $0.isEnabled.toggle() } }
                Button("Reset Gain") { update(band.id) { $0.gainDB = 0 } }
                Divider()
                Button("Delete Band", role: .destructive) { removeBand(band.id) }
            }
            .help("\(band.type.title) · \(Int(band.frequency)) Hz · \(String(format: "%+.1f", band.gainDB)) dB · Q \(String(format: "%.2f", band.q))\nShift: gain only · Option: frequency only · Scroll: Q")
    }

    // MARK: - Band strip

    private var bandStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(settings.parametricBands.enumerated()), id: \.element.id) { index, band in
                Button { selectedID = band.id } label: {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .frame(width: 22, height: 20)
                        .foregroundStyle(band.id == selectedID ? Color.white : DesignTokens.Colors.textSecondary)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(band.id == selectedID ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.sliderTrack))
                        .opacity(band.isEnabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
            }
            if settings.parametricBands.count < EQSettings.bandCount {
                Button(action: addBand) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 20)
                        .foregroundStyle(DesignTokens.Colors.interactiveDefault)
                }
                .buttonStyle(.plain)
                .help("Add band")
            }
            Spacer()
            if spectrumSource != nil {
                Toggle(isOn: $analyzerEnabled) {
                    Label("Analyzer", systemImage: "waveform")
                        .font(DesignTokens.Typography.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(analyzerEnabled ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.textSecondary)
                .help("Show live spectrum of this app's audio behind the curve")
            }
            Button(action: resetBands) {
                Text("Reset").font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Reset all bands to flat")
        }
    }

    // MARK: - Band editor

    @ViewBuilder
    private func bandEditor(index: Int) -> some View {
        let band = settings.parametricBands[index]
        HStack(spacing: 10) {
            Toggle("", isOn: bandBinding(band.id, \.isEnabled))
                .toggleStyle(.switch).scaleEffect(0.65).labelsHidden().frame(width: 34)

            Picker("", selection: bandBinding(band.id, \.type)) {
                ForEach(EQFilterType.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 100)

            EQNumberField(label: "Hz", value: bandBinding(band.id, \.frequency),
                          range: ParametricBand.minFrequency...ParametricBand.maxFrequency, decimals: 0)
            EQNumberField(label: "dB",
                          value: Binding(get: { Double(band.gainDB) },
                                         set: { v in update(band.id) { $0.gainDB = ParametricBand.clampGain(Float(v)) } }),
                          range: Double(EQSettings.minGainDB)...Double(EQSettings.maxGainDB), decimals: 1)
                .disabled(!band.type.usesGain).opacity(band.type.usesGain ? 1 : 0.35)
            EQNumberField(label: "Q", value: bandBinding(band.id, \.q),
                          range: ParametricBand.minQ...ParametricBand.maxQ, decimals: 2)

            Button { removeBand(band.id) } label: {
                Image(systemName: "trash").font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain).help("Remove band")
        }
    }

    // MARK: - Mutations

    private func bandBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<ParametricBand, T>) -> Binding<T> {
        Binding(
            get: { settings.parametricBands.first { $0.id == id }?[keyPath: keyPath] ?? ParametricBand()[keyPath: keyPath] },
            set: { newValue in update(id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func update(_ id: UUID, _ change: (inout ParametricBand) -> Void) {
        guard let i = settings.parametricBands.firstIndex(where: { $0.id == id }) else { return }
        change(&settings.parametricBands[i])
        settings.parametricBands[i] = ParametricBand(
            id: id, isEnabled: settings.parametricBands[i].isEnabled, type: settings.parametricBands[i].type,
            frequency: settings.parametricBands[i].frequency, gainDB: settings.parametricBands[i].gainDB,
            q: settings.parametricBands[i].q)  // re-clamp
        onSettingsChanged(settings)
    }

    private func addBand() {
        guard settings.parametricBands.count < EQSettings.bandCount else { return }
        let band = ParametricBand(frequency: 1000)
        settings.parametricBands.append(band)
        selectedID = band.id
        onSettingsChanged(settings)
    }

    private func addBand(atX px: CGFloat, y py: CGFloat, size: CGSize) {
        guard settings.parametricBands.count < EQSettings.bandCount else { return }
        let rawGain = g.gain(forY: py, height: size.height)
        let band = ParametricBand(
            frequency: g.frequency(forX: px, width: size.width),
            gainDB: (rawGain / EQSettings.gainStepDB).rounded() * EQSettings.gainStepDB)
        settings.parametricBands.append(band)
        selectedID = band.id
        onSettingsChanged(settings)
    }

    private func removeBand(_ id: UUID) {
        guard let i = settings.parametricBands.firstIndex(where: { $0.id == id }) else { return }
        settings.parametricBands.remove(at: i)
        selectedID = settings.parametricBands.indices.contains(i) ? settings.parametricBands[i].id : settings.parametricBands.last?.id
        onSettingsChanged(settings)
    }

    private func resetBands() {
        settings.parametricBands = ParametricBand.defaultBands
        selectedID = settings.parametricBands.first?.id
        onSettingsChanged(settings)
    }
}

/// Compact labelled numeric entry that commits on Return and clamps to a range.
struct EQNumberField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let decimals: Int

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 52)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(DesignTokens.Colors.sliderTrack))
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Text(label).font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .onAppear(perform: refresh)
        .onChange(of: value) { _, _ in if !focused { refresh() } }
    }

    private func refresh() { text = String(format: "%.\(decimals)f", value) }

    private func commit() {
        let parsed = Double(text.replacingOccurrences(of: ",", with: "."))
        if let parsed, parsed.isFinite { value = min(max(parsed, range.lowerBound), range.upperBound) }
        refresh()
    }
}
