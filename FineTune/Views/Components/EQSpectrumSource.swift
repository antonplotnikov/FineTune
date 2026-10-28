// FineTune/Views/Components/EQSpectrumSource.swift
import SwiftUI

/// Connects an EQ panel to the live spectrum of the app it edits. Injected per row through the
/// environment so `EQPanelView` doesn't need engine access (or dozens more init parameters).
struct EQSpectrumSource {
    /// Turns audio-thread capture on/off. The panel enables it only while the analyzer is visible.
    let setActive: @MainActor (Bool) -> Void
    /// Latest log-spaced dBFS spectrum, or nil if unavailable.
    let frame: @MainActor () -> [Float]?
}

private struct EQSpectrumSourceKey: EnvironmentKey {
    static let defaultValue: EQSpectrumSource? = nil
}

extension EnvironmentValues {
    var eqSpectrumSource: EQSpectrumSource? {
        get { self[EQSpectrumSourceKey.self] }
        set { self[EQSpectrumSourceKey.self] = newValue }
    }
}
