import Foundation

/// "Music through concrete" effect built from real biquad sections, so it runs in both the
/// process tap and the browser extension's Web Audio graph.
///
/// - `distance` and `wallThickness` (0...1) both lower the low-pass cutoff and the level;
///   wall thickness also steepens the roll-off (24 dB/oct up to 48 dB/oct).
nonisolated struct WallEffect: Codable, Equatable {
    var distance: Double
    var wallThickness: Double

    static let `default` = WallEffect(distance: 0.7, wallThickness: 0.7)

    init(distance: Double, wallThickness: Double) {
        self.distance = Self.clamp(distance)
        self.wallThickness = Self.clamp(wallThickness)
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : 0.7
    }

    /// 0 = thin wall, close by; 1 = thick walls, far away.
    var attenuation: Double { (distance + wallThickness) / 2 }

    /// Low-pass corner: about 260 Hz for the thinnest setting down to about 117 Hz.
    var cutoffHz: Double { 260 * pow(0.45, attenuation) }

    /// Cascaded 2nd-order low-pass sections: 2 (24 dB/oct) ... 4 (48 dB/oct).
    var lowPassSections: Int { 2 + Int((wallThickness * 2).rounded()) }

    /// Level loss for the whole path, -6 dB (thin) ... -18 dB (the preamp limit).
    var preampDB: Float { Float(max(-18, -6 - 12 * attenuation)) }

    var bands: [ParametricBand] {
        var specs: [(EQFilterType, Double, Float, Double)] = [
            (.highPass, 40, 0, 0.8),
            // Soft low-end body; the walls pass bass, not a boosted one.
            (.peaking, 80, Float(1 + wallThickness), 0.9),
        ]
        // Q 0.71 sections stack without resonance and mean the same in RBJ form and Web Audio.
        for _ in 0..<lowPassSections { specs.append((.lowPass, cutoffHz, 0, 0.71)) }
        return ParametricBand.preset(specs)
    }
}

extension EQSettings {
    /// A parametric EQ rendering `effect`, remembering its parameters so the UI can show sliders.
    static func wall(_ effect: WallEffect) -> EQSettings {
        var settings = EQSettings(mode: .parametric, parametricBands: effect.bands, preampDB: effect.preampDB)
        settings.wallEffect = effect
        return settings
    }

    /// The effect parameters, only while the curve still is the one they generate (manual edits hide it).
    var activeWallEffect: WallEffect? {
        guard let wallEffect, hasSameCurve(as: .wall(wallEffect)) else { return nil }
        return wallEffect
    }
}
