import Foundation

/// Audio EQ Cookbook biquad coefficient calculations
/// Reference: Robert Bristow-Johnson's Audio EQ Cookbook
enum BiquadMath {
    /// Standard Q for graphic EQ (overlapping bands)
    static let graphicEQQ: Double = 1.4

    /// Compute peaking EQ biquad coefficients
    /// Returns [b0, b1, b2, a1, a2] normalized by a0 for vDSP_biquad
    static func peakingEQCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosW
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosW
        let a2 = 1.0 - alpha / A

        // Normalize by a0 for vDSP_biquad format
        // vDSP difference equation: y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
        // Coefficients are passed as-is (vDSP internally subtracts a1/a2)
        return [
            b0 / a0,
            b1 / a0,
            b2 / a0,
            a1 / a0,
            a2 / a0
        ]
    }

    /// Compute low shelf biquad coefficients (RBJ cookbook)
    /// Returns [b0, b1, b2, a1, a2] normalized by a0 for vDSP_biquad
    static func lowShelfCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha

        let b0 = A * ((A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha)
        let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW)
        let b2 = A * ((A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha)
        let a0 = (A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha
        let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW)
        let a2 = (A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    /// Compute high shelf biquad coefficients (RBJ cookbook)
    /// Returns [b0, b1, b2, a1, a2] normalized by a0 for vDSP_biquad
    static func highShelfCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha

        let b0 = A * ((A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha)
        let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW)
        let b2 = A * ((A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha)
        let a0 = (A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha
        let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW)
        let a2 = (A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    /// Compute high-pass biquad coefficients (RBJ cookbook, 2nd-order Butterworth)
    /// Returns [b0, b1, b2, a1, a2] normalized by a0 for vDSP_biquad
    static func highPassCoefficients(
        frequency: Double,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let b0 =  (1.0 + cosW) / 2.0
        let b1 = -(1.0 + cosW)
        let b2 =  (1.0 + cosW) / 2.0
        let a0 =  1.0 + alpha
        let a1 = -2.0 * cosW
        let a2 =  1.0 - alpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    /// Compute low-pass biquad coefficients (RBJ cookbook)
    static func lowPassCoefficients(
        frequency: Double,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let b0 = (1.0 - cosW) / 2.0
        let b1 = 1.0 - cosW
        let b2 = (1.0 - cosW) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW
        let a2 = 1.0 - alpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    /// Compute notch biquad coefficients (RBJ cookbook)
    static func notchCoefficients(
        frequency: Double,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let a0 = 1.0 + alpha
        return [1.0 / a0, (-2.0 * cosW) / a0, 1.0 / a0, (-2.0 * cosW) / a0, (1.0 - alpha) / a0]
    }

    /// Unity (passthrough) section.
    static let unityCoefficients: [Double] = [1.0, 0.0, 0.0, 0.0, 0.0]

    /// Coefficients for one parametric band. Disabled, neutral, or at/above-Nyquist bands bypass.
    static func coefficients(for band: ParametricBand, sampleRate: Double) -> [Double] {
        guard !band.isNeutral, band.frequency < sampleRate / 2.0 else { return unityCoefficients }
        switch band.type {
        case .peaking:
            return peakingEQCoefficients(frequency: band.frequency, gainDB: band.gainDB, q: band.q, sampleRate: sampleRate)
        case .lowShelf:
            return lowShelfCoefficients(frequency: band.frequency, gainDB: band.gainDB, q: band.q, sampleRate: sampleRate)
        case .highShelf:
            return highShelfCoefficients(frequency: band.frequency, gainDB: band.gainDB, q: band.q, sampleRate: sampleRate)
        case .highPass:
            return highPassCoefficients(frequency: band.frequency, q: band.q, sampleRate: sampleRate)
        case .lowPass:
            return lowPassCoefficients(frequency: band.frequency, q: band.q, sampleRate: sampleRate)
        case .notch:
            return notchCoefficients(frequency: band.frequency, q: band.q, sampleRate: sampleRate)
        }
    }

    /// Coefficients for all `EQSettings.bandCount` sections of an EQ in either mode.
    /// Returns 50 Doubles, padding unused parametric slots with unity.
    static func coefficients(for settings: EQSettings, sampleRate: Double) -> [Double] {
        var all = curveCoefficients(for: settings, sampleRate: sampleRate)
        // Fold the preamp into the first section's numerator: scaling b0..b2 scales the whole
        // cascade's gain, so the preamp costs nothing extra on the audio thread.
        let preamp = Double(pow(10.0, Double(EQSettings.clampPreamp(settings.preampDB)) / 20.0))
        if preamp != 1.0 {
            for i in 0..<3 { all[i] *= preamp }
        }
        return all
    }

    /// Section coefficients for the curve alone (no preamp).
    private static func curveCoefficients(for settings: EQSettings, sampleRate: Double) -> [Double] {
        switch settings.mode {
        case .graphic:
            return coefficientsForAllBands(gains: settings.clampedGains, sampleRate: sampleRate)
        case .parametric:
            var all: [Double] = []
            all.reserveCapacity(EQSettings.bandCount * 5)
            for band in settings.clampedParametricBands {
                all.append(contentsOf: coefficients(for: band, sampleRate: sampleRate))
            }
            for _ in settings.parametricBands.count..<EQSettings.bandCount {
                all.append(contentsOf: unityCoefficients)
            }
            return all
        }
    }

    /// Highest boost (dB, never below 0) the curve applies anywhere in 20 Hz–20 kHz, ignoring preamp.
    static func peakBoostDB(for settings: EQSettings, sampleRate: Double = 48_000) -> Double {
        let coeffs = curveCoefficients(for: settings, sampleRate: sampleRate)
        let lo = log10(ParametricBand.minFrequency), hi = log10(ParametricBand.maxFrequency)
        var peak = 0.0
        for i in 0...256 {
            let f = pow(10, lo + (hi - lo) * Double(i) / 256)
            peak = max(peak, magnitudeResponseDB(coefficients: coeffs, frequency: f, sampleRate: sampleRate))
        }
        return peak
    }

    /// Preamp that cancels the curve's peak boost (0 for cut-only curves), rounded to 0.1 dB.
    static func autoPreampDB(for settings: EQSettings, sampleRate: Double = 48_000) -> Float {
        let needed = -Float(peakBoostDB(for: settings, sampleRate: sampleRate))
        return EQSettings.clampPreamp((needed * 10).rounded(.down) / 10)
    }

    /// Magnitude (dB) of a cascade of biquad sections at `frequency`, for drawing the response curve.
    /// `coefficients` is the flat [b0,b1,b2,a1,a2]×N layout used by vDSP_biquad.
    static func magnitudeResponseDB(coefficients: [Double], frequency: Double, sampleRate: Double) -> Double {
        let w = 2.0 * .pi * frequency / sampleRate
        let cos1 = cos(w), sin1 = sin(w), cos2 = cos(2 * w), sin2 = sin(2 * w)
        var totalDB = 0.0
        for i in stride(from: 0, to: coefficients.count - 4, by: 5) {
            let b0 = coefficients[i], b1 = coefficients[i + 1], b2 = coefficients[i + 2]
            let a1 = coefficients[i + 3], a2 = coefficients[i + 4]
            // H(e^jw) = (b0 + b1 e^-jw + b2 e^-j2w) / (1 + a1 e^-jw + a2 e^-j2w)
            let nr = b0 + b1 * cos1 + b2 * cos2, ni = -(b1 * sin1 + b2 * sin2)
            let dr = 1 + a1 * cos1 + a2 * cos2, di = -(a1 * sin1 + a2 * sin2)
            let num = nr * nr + ni * ni, den = max(dr * dr + di * di, 1e-30)
            totalDB += 10 * log10(max(num / den, 1e-30))
        }
        return totalDB
    }

    /// Correct a filter frequency optimized at `sourceRate` for use at `targetRate`.
    /// Uses inverse bilinear transform (digital→analog) then forward (analog→digital).
    static func preWarpFrequency(
        _ freq: Double,
        from sourceRate: Double,
        to targetRate: Double
    ) -> Double {
        // Map from source digital domain to analog (undo source bilinear transform)
        let fAnalog = (sourceRate / .pi) * tan(.pi * freq / sourceRate)
        // Map from analog to target digital domain (apply target bilinear transform)
        return (targetRate / .pi) * atan(.pi * fAnalog / targetRate)
    }

    /// Compute coefficients for AutoEQ filters (peaking, lowShelf, highShelf).
    /// Returns flat array of 5*N Doubles for vDSP_biquad_CreateSetup.
    ///
    /// - Parameters:
    ///   - filters: Filter parameters from an AutoEQ profile.
    ///   - sampleRate: Device's actual sample rate (Hz).
    ///   - profileOptimizedRate: Sample rate the profile was optimized for (Hz).
    ///     When different from `sampleRate`, filter frequencies are pre-warped to
    ///     compensate for the bilinear transform's frequency warping.
    static func coefficientsForAutoEQFilters(
        _ filters: [AutoEQFilter],
        sampleRate: Double,
        profileOptimizedRate: Double = 48000
    ) -> [Double] {
        var allCoeffs: [Double] = []
        allCoeffs.reserveCapacity(filters.count * 5)

        let needsPreWarp = abs(profileOptimizedRate - sampleRate) > 1.0

        for filter in filters {
            var frequency = filter.frequency

            // Pre-warp frequency if profile was optimized for a different sample rate
            if needsPreWarp {
                frequency = preWarpFrequency(frequency, from: profileOptimizedRate, to: sampleRate)
            }

            // Bypass invalid or above-Nyquist filters (pre-warp can produce
            // negative frequencies when the source filter is above its own Nyquist)
            if frequency <= 0 || frequency >= sampleRate / 2.0 {
                allCoeffs.append(contentsOf: [1.0, 0.0, 0.0, 0.0, 0.0])
                continue
            }

            let coeffs: [Double]
            switch filter.type {
            case .peaking:
                coeffs = peakingEQCoefficients(
                    frequency: frequency, gainDB: filter.gainDB,
                    q: filter.q, sampleRate: sampleRate)
            case .lowShelf:
                coeffs = lowShelfCoefficients(
                    frequency: frequency, gainDB: filter.gainDB,
                    q: filter.q, sampleRate: sampleRate)
            case .highShelf:
                coeffs = highShelfCoefficients(
                    frequency: frequency, gainDB: filter.gainDB,
                    q: filter.q, sampleRate: sampleRate)
            }
            allCoeffs.append(contentsOf: coeffs)
        }

        return allCoeffs
    }

    /// Compute coefficients for all 10 bands
    /// Returns 50 Doubles: [band0: b0,b1,b2,a1,a2, band1: ..., ...]
    static func coefficientsForAllBands(
        gains: [Float],
        sampleRate: Double
    ) -> [Double] {
        guard gains.count == EQSettings.bandCount else {
            // Return unity (passthrough) coefficients for all bands
            return (0..<EQSettings.bandCount).flatMap { _ in [1.0, 0.0, 0.0, 0.0, 0.0] }
        }

        var allCoeffs: [Double] = []
        allCoeffs.reserveCapacity(50)

        for (index, frequency) in EQSettings.frequencies.enumerated() {
            // Bands at or above Nyquist cannot exist in the signal — bypass with unity gain.
            // Without this guard, omega > pi produces negative alpha, yielding unstable
            // biquad coefficients (poles outside the unit circle) that cause exponentially
            // growing output heard as robotic/static distortion.
            if frequency >= sampleRate / 2.0 {
                allCoeffs.append(contentsOf: [1.0, 0.0, 0.0, 0.0, 0.0])
                continue
            }
            let bandCoeffs = peakingEQCoefficients(
                frequency: frequency,
                gainDB: gains[index],
                q: graphicEQQ,
                sampleRate: sampleRate
            )
            allCoeffs.append(contentsOf: bandCoeffs)
        }

        return allCoeffs
    }
}
