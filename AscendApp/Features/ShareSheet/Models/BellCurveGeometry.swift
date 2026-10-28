import Foundation

/// The bell curve behind the Curve card and the bell-curve stickers: an idealised normal curve with
/// the climber's marker at their percentile.
struct BellCurveGeometry: Equatable, Sendable {
    /// Points of the full outline, left to right, in a `width` by `height` box (y grows downward).
    let outline: [CGPoint]
    /// The marker's position on the curve.
    let marker: CGPoint

    /// - Parameters:
    ///   - percentile: The share of the field this finish beat, 0 to 1. `1 - position / field`.
    ///   - width: The drawing width.
    ///   - height: The drawing height.
    init(percentile: Double, width: Double, height: Double) {
        let p = min(max(percentile, 0.005), 0.995)
        let z = BellCurveGeometry.inverseNormal(p)
        let samples = 120
        var points: [CGPoint] = []
        for index in 0...samples {
            let x = Double(index) / Double(samples) * 6 - 3
            let y = BellCurveGeometry.density(x) / BellCurveGeometry.density(0)
            points.append(CGPoint(x: (x + 3) / 6 * width, y: height - y * (height - 6)))
        }
        outline = points
        let markerY = BellCurveGeometry.density(z) / BellCurveGeometry.density(0)
        marker = CGPoint(x: (min(max(z, -3), 3) + 3) / 6 * width, y: height - markerY * (height - 6))
    }

    /// The outline up to the marker, closed along the baseline: the area the finish beat.
    var beatenPoints: [CGPoint] {
        outline.filter { $0.x <= marker.x }
    }

    static func density(_ x: Double) -> Double {
        exp(-x * x / 2) / (2 * Double.pi).squareRoot()
    }

    /// Acklam's rational approximation of the inverse normal CDF, accurate to about 1e-9.
    static func inverseNormal(_ p: Double) -> Double {
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                 3.754408661907416e+00]
        let low = 0.02425
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > 1 - low {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }
}
