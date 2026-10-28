// FineTune/Views/ChannelDSPPanels.swift
import SwiftUI

/// Slider with an exact numeric field, used by the dynamics and spatial panels.
struct DSPSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let decimals: Int
    let unit: String
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 62, alignment: .leading)
            LiquidGlassSlider(value: $value, in: range)
                .frame(minWidth: 70)
            EQNumberField(label: unit, value: $value, range: range, decimals: decimals)
        }
        .opacity(isEnabled ? 1 : 0.35)
        .allowsHitTesting(isEnabled)
    }
}

/// Recessed container matching `EQPanelView`'s look.
private struct DSPPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background { RoundedRectangle(cornerRadius: 10).fill(DesignTokens.Colors.recessedBackground) }
            .padding(.horizontal, 2)
            .padding(.vertical, DesignTokens.Spacing.xs)
    }
}

private extension View {
    func dspPanelBackground() -> some View { modifier(DSPPanelBackground()) }
}

// MARK: - Dynamics

struct DynamicsPanelView: View {
    @Binding var settings: ChannelDSPSettings
    let onChange: (ChannelDSPSettings) -> Void
    let gainReduction: () -> Float

    private var dynamics: Binding<DynamicsSettings> {
        Binding(get: { settings.dynamics }, set: { settings.dynamics = $0.clamped; onChange(settings) })
    }

    private var currentPresetName: String {
        DynamicsPreset.allCases.first { $0.settings == settings.dynamics }?.name ?? "Custom"
    }

    private func bind(_ keyPath: WritableKeyPath<DynamicsSettings, Double>) -> Binding<Double> {
        Binding(get: { settings.dynamics[keyPath: keyPath] },
                set: { settings.dynamics[keyPath: keyPath] = $0; settings.dynamics = settings.dynamics.clamped; onChange(settings) })
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Dynamics")
                    .font(DesignTokens.Typography.pickerText)
                Spacer()
                gainReductionMeter
                Menu {
                    ForEach(DynamicsPreset.allCases) { preset in
                        Button(preset.name) {
                            settings.dynamics = preset.settings
                            onChange(settings)
                        }
                    }
                } label: {
                    Text(currentPresetName).font(DesignTokens.Typography.pickerText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(alignment: .top, spacing: 18) {
                // Compressor
                VStack(spacing: 6) {
                    Toggle(isOn: Binding(get: { settings.dynamics.compressorEnabled },
                                         set: { settings.dynamics.compressorEnabled = $0; onChange(settings) })) {
                        Text("Compressor").font(DesignTokens.Typography.pickerText)
                    }
                    .toggleStyle(.switch).controlSize(.mini)

                    let on = settings.dynamics.compressorEnabled
                    DSPSliderRow(label: "Threshold", value: bind(\.thresholdDB), range: DynamicsSettings.thresholdRange, decimals: 1, unit: "dB", isEnabled: on)
                    DSPSliderRow(label: "Ratio", value: bind(\.ratio), range: DynamicsSettings.ratioRange, decimals: 1, unit: ":1", isEnabled: on)
                    DSPSliderRow(label: "Attack", value: bind(\.attackMs), range: DynamicsSettings.attackRange, decimals: 1, unit: "ms", isEnabled: on)
                    DSPSliderRow(label: "Release", value: bind(\.releaseMs), range: DynamicsSettings.releaseRange, decimals: 0, unit: "ms", isEnabled: on)
                    DSPSliderRow(label: "Knee", value: bind(\.kneeDB), range: DynamicsSettings.kneeRange, decimals: 1, unit: "dB", isEnabled: on)
                    DSPSliderRow(label: "Makeup", value: bind(\.makeupDB), range: DynamicsSettings.makeupRange, decimals: 1, unit: "dB", isEnabled: on)
                }
                .frame(maxWidth: .infinity)

                // Limiter
                VStack(spacing: 6) {
                    Toggle(isOn: Binding(get: { settings.dynamics.limiterEnabled },
                                         set: { settings.dynamics.limiterEnabled = $0; onChange(settings) })) {
                        Text("Limiter").font(DesignTokens.Typography.pickerText)
                    }
                    .toggleStyle(.switch).controlSize(.mini)

                    let on = settings.dynamics.limiterEnabled
                    DSPSliderRow(label: "Ceiling", value: bind(\.ceilingDB), range: DynamicsSettings.ceilingRange, decimals: 1, unit: "dB", isEnabled: on)
                    DSPSliderRow(label: "Release", value: bind(\.limiterReleaseMs), range: DynamicsSettings.limiterReleaseRange, decimals: 0, unit: "ms", isEnabled: on)
                    Text("Look-ahead limiter: catches peaks before they reach the output (adds under 1 ms of delay).")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .dspPanelBackground()
    }

    /// Live "how much is the dynamics stage squashing" readout.
    private var gainReductionMeter: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !settings.dynamics.isActive)) { _ in
            let reduction = settings.dynamics.isActive ? gainReduction() : 0
            HStack(spacing: 4) {
                Text("GR")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.Colors.sliderTrack).frame(width: 70, height: 4)
                    Capsule().fill(reduction > 12 ? Color.orange : DesignTokens.Colors.accentPrimary)
                        .frame(width: 70 * CGFloat(min(reduction, 24) / 24), height: 4)
                }
                Text(String(format: "-%.1f dB", reduction))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - Spatial

struct SpatialPanelView: View {
    @Binding var settings: ChannelDSPSettings
    let onChange: (ChannelDSPSettings) -> Void

    private var currentPresetName: String {
        SpatialPreset.allCases.first { $0.settings == settings.spatial }?.name
            ?? (settings.spatial.isEnabled ? "Custom" : "Off")
    }

    private func bind(_ keyPath: WritableKeyPath<SpatialSettings, Double>, scale: Double) -> Binding<Double> {
        Binding(get: { settings.spatial[keyPath: keyPath] * scale },
                set: { settings.spatial[keyPath: keyPath] = $0 / scale; settings.spatial = settings.spatial.clamped; onChange(settings) })
    }

    var body: some View {
        let on = settings.spatial.isEnabled
        VStack(spacing: 10) {
            HStack {
                Toggle(isOn: Binding(get: { settings.spatial.isEnabled },
                                     set: { settings.spatial.isEnabled = $0; onChange(settings) })) {
                    Text("Spatial").font(DesignTokens.Typography.pickerText)
                }
                .toggleStyle(.switch).controlSize(.mini)
                Spacer()
                Menu {
                    ForEach(SpatialPreset.allCases) { preset in
                        Button(preset.name) {
                            settings.spatial = preset.settings
                            onChange(settings)
                        }
                    }
                } label: {
                    Text(currentPresetName).font(DesignTokens.Typography.pickerText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            DSPSliderRow(label: "Width", value: bind(\.width, scale: 100), range: 0...200, decimals: 0, unit: "%", isEnabled: on)

            // Binaural (HRTF) rendering
            VStack(spacing: 6) {
                Toggle(isOn: Binding(get: { settings.spatial.binaural },
                                     set: { settings.spatial.binaural = $0; onChange(settings) })) {
                    Text("Binaural (HRTF)").font(DesignTokens.Typography.pickerText)
                }
                .toggleStyle(.switch).controlSize(.mini)
                .disabled(!on)

                let binauralOn = on && settings.spatial.binaural
                DSPSliderRow(label: "Speakers", value: bind(\.speakerAngle, scale: 1),
                             range: SpatialSettings.speakerAngleRange, decimals: 0, unit: "°", isEnabled: binauralOn)
                DSPSliderRow(label: "Binaural", value: bind(\.binauralMix, scale: 100),
                             range: 0...100, decimals: 0, unit: "%", isEnabled: binauralOn)
            }

            DSPSliderRow(label: "Crossfeed", value: bind(\.crossfeed, scale: 100), range: 0...100, decimals: 0, unit: "%",
                         isEnabled: on && !settings.spatial.binaural)
            DSPSliderRow(label: "Room", value: bind(\.room, scale: 100), range: 0...100, decimals: 0, unit: "%", isEnabled: on)

            Text("Binaural places your stereo mix on two virtual speakers using measured head-related transfer functions (MIT KEMAR dummy head), so sound seems to come from outside your head. Use headphones. Speakers sets how far apart they sit (30° is the classic stereo triangle; wider gives a bigger stage). Crossfeed is a simpler alternative and is replaced while Binaural is on. Applies to stereo output.")
                .font(.system(size: 9))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dspPanelBackground()
    }
}
