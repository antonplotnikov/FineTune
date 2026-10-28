// FineTune/Views/Components/ChannelDSPSource.swift
import SwiftUI

/// Gives an app row access to its dynamics/spatial settings and live gain-reduction meter,
/// injected through the environment (same pattern as `EQSpectrumSource`) so `AppRow`
/// doesn't need more initializer parameters.
struct ChannelDSPSource {
    let settings: @MainActor () -> ChannelDSPSettings
    let update: @MainActor (ChannelDSPSettings) -> Void
    let gainReduction: @MainActor () -> Float
}

private struct ChannelDSPSourceKey: EnvironmentKey {
    static let defaultValue: ChannelDSPSource? = nil
}

extension EnvironmentValues {
    var channelDSPSource: ChannelDSPSource? {
        get { self[ChannelDSPSourceKey.self] }
        set { self[ChannelDSPSourceKey.self] = newValue }
    }
}
