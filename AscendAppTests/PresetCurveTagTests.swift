import CoreGraphics
import Testing
@testable import AscendApp

/// The `YOU · #806` tag on the Curve card never sits on the marker's dot or under the curve's line,
/// wherever on the curve a finish lands and however many digits its rank has. Mid-field finishes,
/// which the TOP 50% boundary puts right at the peak, used to draw the tag through the dot, and a
/// finish at either tail drew the rising curve through `YOU · #1`.
struct PresetCurveTagTests {
    private struct Placement {
        let text: CGRect
        let dot: CGRect
        let outline: [CGPoint]
    }

    private static let percentiles = [0.0, 1 - 1.0 / 914] + stride(from: 0.005, through: 0.995, by: 0.005).map { $0 }
    /// 1 to 7 digit ranks, grouped as the card prints them, up to `#1,234,567`.
    private static let positions = [1, 12, 123, 1_234, 12_345, 123_456, 1_234_567]

    @MainActor
    private func placement(percentile: Double, position: Int) -> Placement {
        let geometry = BellCurveGeometry(
            percentile: percentile,
            width: Double(PresetCurveLayout.curveWidth),
            height: Double(PresetCurveLayout.curveHeight)
        )
        let rank = ShareSheetSubject.Rank(position: position, field: 2_000_000)!
        let text = PresetCurveLayout.tagFrame(text: PresetCurveLayout.tagText(rank), geometry: geometry)
        let r = PresetCurveLayout.dotRadius
        let marker = geometry.marker
        return Placement(
            text: text,
            dot: CGRect(x: marker.x - r, y: marker.y - r, width: r * 2, height: r * 2),
            outline: geometry.outline
        )
    }

    /// Whether the segment from `a` to `b` passes through `rect`, by clipping it to the rect's x span.
    private func segment(_ a: CGPoint, _ b: CGPoint, crosses rect: CGRect) -> Bool {
        let minX = max(min(a.x, b.x), rect.minX)
        let maxX = min(max(a.x, b.x), rect.maxX)
        guard minX <= maxX else { return false }
        func y(at x: CGFloat) -> CGFloat { b.x == a.x ? a.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x) }
        let low = min(y(at: minX), y(at: maxX))
        let high = max(y(at: minX), y(at: maxX))
        return low <= rect.maxY && high >= rect.minY
    }

    @MainActor
    @Test(arguments: percentiles, positions)
    func theTagStaysClearOfTheCurveAndTheMarker(percentile: Double, position: Int) {
        let found = placement(percentile: percentile, position: position)
        let crossing = zip(found.outline, found.outline.dropFirst()).first { segment($0, $1, crosses: found.text) }
        #expect(crossing == nil, "at \(percentile), #\(position): the curve \(String(describing: crossing)) crosses the tag \(found.text)")
        #expect(!found.text.intersects(found.dot), "at \(percentile), #\(position): the tag \(found.text) covers the dot \(found.dot)")
        #expect(found.text.minX >= 0 && found.text.maxX <= PresetCurveLayout.curveWidth, "at \(percentile), #\(position): the tag \(found.text) leaves the curve's box")
        #expect(found.text.minY >= 0, "at \(percentile), #\(position): the tag \(found.text) rises out of the curve's box")
    }

}
