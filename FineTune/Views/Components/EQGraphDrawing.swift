// FineTune/Views/Components/EQGraphDrawing.swift
import SwiftUI

/// Shared geometry and drawing for the EQ response graph (log frequency, linear dB).
struct EQGraphDrawing {
    var displayRate: Double = 48_000
    var dbRange: Double = Double(EQSettings.maxGainDB)

    // MARK: Coordinate mapping

    func x(for frequency: Double, width: CGFloat) -> CGFloat {
        let lo = log10(ParametricBand.minFrequency), hi = log10(ParametricBand.maxFrequency)
        return CGFloat((log10(frequency) - lo) / (hi - lo)) * width
    }

    func frequency(forX x: CGFloat, width: CGFloat) -> Double {
        let lo = log10(ParametricBand.minFrequency), hi = log10(ParametricBand.maxFrequency)
        let t = Double(min(max(x / width, 0), 1))
        return pow(10, lo + t * (hi - lo))
    }

    func y(for db: Double, height: CGFloat) -> CGFloat {
        CGFloat(0.5 - db / (2 * dbRange)) * height
    }

    func gain(forY y: CGFloat, height: CGFloat) -> Float {
        let t = Double(min(max(y / height, 0), 1))
        return Float((0.5 - t) * 2 * dbRange)
    }

    // MARK: Drawing

    func drawGrid(_ ctx: GraphicsContext, size: CGSize) {
        let line = DesignTokens.Colors.textTertiary.opacity(0.25)
        let label = DesignTokens.Colors.textTertiary
        for f in [50.0, 100, 200, 500, 1_000, 2_000, 5_000, 10_000] {
            var p = Path()
            let px = x(for: f, width: size.width)
            p.move(to: CGPoint(x: px, y: 0)); p.addLine(to: CGPoint(x: px, y: size.height))
            let major = f == 100 || f == 1_000 || f == 10_000
            ctx.stroke(p, with: .color(line.opacity(major ? 1 : 0.5)), lineWidth: 0.5)
            if major || f == 50 || f == 500 || f == 5_000 {
                ctx.draw(Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))")
                    .font(.system(size: 8)).foregroundColor(label),
                         at: CGPoint(x: px + 8, y: size.height - 6))
            }
        }
        for db in stride(from: -12.0, through: 12.0, by: 6.0) {
            var p = Path()
            let py = y(for: db, height: size.height)
            p.move(to: CGPoint(x: 0, y: py)); p.addLine(to: CGPoint(x: size.width, y: py))
            ctx.stroke(p, with: .color(db == 0 ? DesignTokens.Colors.unityMarker : line),
                       lineWidth: db == 0 ? 1 : 0.5)
            ctx.draw(Text(db == 0 ? "0" : String(format: "%+.0f", db))
                .font(.system(size: 8)).foregroundColor(label),
                     at: CGPoint(x: 10, y: py - 6))
        }
    }

    /// Response of the whole EQ (including preamp) as a stroked curve.
    func drawCurve(_ ctx: GraphicsContext, size: CGSize, settings: EQSettings) {
        let coeffs = BiquadMath.coefficients(for: settings, sampleRate: displayRate)
        var path = Path()
        let steps = 160
        for i in 0...steps {
            let px = size.width * CGFloat(i) / CGFloat(steps)
            let f = frequency(forX: px, width: size.width)
            let db = BiquadMath.magnitudeResponseDB(coefficients: coeffs, frequency: f, sampleRate: displayRate)
            let pt = CGPoint(x: px, y: y(for: max(-dbRange, min(dbRange, db)), height: size.height))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(DesignTokens.Colors.accentPrimary), lineWidth: 1.5)
    }

    /// Filled spectrum behind the curve: -90 dBFS at the bottom edge, 0 dBFS at the top.
    func drawSpectrum(_ ctx: GraphicsContext, size: CGSize, db: [Float]) {
        guard db.count > 1 else { return }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, value) in db.enumerated() {
            let px = size.width * CGFloat(i) / CGFloat(db.count - 1)
            let t = CGFloat(max(0, min(1, (value - SpectrumAnalyzer.floorDB) / -SpectrumAnalyzer.floorDB)))
            path.addLine(to: CGPoint(x: px, y: size.height * (1 - t)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [DesignTokens.Colors.accentPrimary.opacity(0.35), DesignTokens.Colors.accentPrimary.opacity(0.04)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }
}

/// Read-only response graph with optional live spectrum, shown above the graphic EQ sliders.
struct EQResponseGraphView: View {
    let settings: EQSettings
    @Environment(\.eqSpectrumSource) private var spectrumSource
    @AppStorage("eqAnalyzerEnabled") private var analyzerEnabled = true

    private let drawing = EQGraphDrawing()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(analyzerEnabled && spectrumSource != nil))) { _ in
            Canvas { ctx, size in
                drawing.drawGrid(ctx, size: size)
                if analyzerEnabled, let db = spectrumSource?.frame() { drawing.drawSpectrum(ctx, size: size, db: db) }
                drawing.drawCurve(ctx, size: size, settings: settings)
            }
        }
        .frame(height: 70)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { spectrumSource?.setActive(analyzerEnabled) }
        .onDisappear { spectrumSource?.setActive(false) }
        .onChange(of: analyzerEnabled) { _, on in spectrumSource?.setActive(on) }
        .overlay(alignment: .topTrailing) {
            if spectrumSource != nil {
                Toggle(isOn: $analyzerEnabled) {
                    Image(systemName: "waveform").font(.system(size: 9))
                }
                .toggleStyle(.button).buttonStyle(.plain)
                .foregroundStyle(analyzerEnabled ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.textSecondary)
                .padding(4)
                .help("Show live spectrum")
            }
        }
        .opacity(settings.isEnabled ? 1 : 0.3)
    }
}
