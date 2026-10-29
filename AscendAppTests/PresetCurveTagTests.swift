import CoreGraphics
import Testing
@testable import AscendApp

/// The `YOU · #806` tag on the Curve card never sits on the marker's dot, wherever on the curve a
/// finish lands. Mid-field finishes, which the TOP 50% boundary puts right at the peak, used to
/// draw the tag straight through the dot.
struct PresetCurveTagTests {
    /// The tag's text can sit anywhere in its box, so the box is what must stay clear of the dot.
    @MainActor
    private func tagBox(percentile: Double, isWide: Bool) -> (box: CGRect, dot: CGRect) {
        let marker = BellCurveGeometry(
            percentile: percentile,
            width: Double(PresetCurveLayout.curveWidth),
            height: Double(PresetCurveLayout.curveHeight)
        ).marker
        let tag = PresetCurveLayout.tag(markerX: marker.x, markerY: marker.y, isWide: isWide)
        let box = CGRect(
            x: marker.x + tag.boxOffset - PresetCurveLayout.tagBoxWidth / 2,
            y: tag.centerY - PresetCurveLayout.tagLineHeight / 2,
            width: PresetCurveLayout.tagBoxWidth,
            height: PresetCurveLayout.tagLineHeight
        )
        let r = PresetCurveLayout.dotRadius
        return (box, CGRect(x: marker.x - r, y: marker.y - r, width: r * 2, height: r * 2))
    }

    @MainActor
    @Test(arguments: stride(from: 0.01, through: 0.99, by: 0.01).map { $0 }, [false, true])
    func theTagNeverCoversTheMarker(percentile: Double, isWide: Bool) {
        let found = tagBox(percentile: percentile, isWide: isWide)
        #expect(!found.box.intersects(found.dot), "at \(percentile) the tag \(found.box) covers the dot \(found.dot)")
    }
}
