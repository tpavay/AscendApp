import Foundation
import Testing
@testable import AscendApp

struct BellCurveGeometryTests {
    @Test
    func theInverseNormalIsZeroAtTheMedianAndSymmetric() {
        #expect(abs(BellCurveGeometry.inverseNormal(0.5)) < 1e-9)
        let upper = BellCurveGeometry.inverseNormal(0.8413447)
        #expect(abs(upper - 1.0) < 1e-3)
        let lower = BellCurveGeometry.inverseNormal(0.1586553)
        #expect(abs(lower + 1.0) < 1e-3)
    }

    @Test
    func theMarkerMovesRightAsMoreOfTheFieldIsBeaten() {
        let low = BellCurveGeometry(percentile: 0.2, width: 270, height: 120)
        let high = BellCurveGeometry(percentile: 0.89, width: 270, height: 120)
        #expect(high.marker.x > low.marker.x)
    }

    @Test
    func theMedianSitsAtTheCentreOnTheTopOfTheCurve() {
        let median = BellCurveGeometry(percentile: 0.5, width: 270, height: 120)
        #expect(abs(median.marker.x - 135) < 0.5)
        #expect(abs(median.marker.y - 6) < 0.5)
    }

    @Test
    func theOutlineSpansTheWholeWidthAndStaysInsideTheBox() {
        let curve = BellCurveGeometry(percentile: 0.7, width: 270, height: 120)
        #expect(curve.outline.first?.x == 0)
        #expect(curve.outline.last?.x == 270)
        for point in curve.outline {
            #expect(point.y >= 0 && point.y <= 120)
        }
    }

    @Test
    func theBeatenAreaStopsAtTheMarker() {
        let curve = BellCurveGeometry(percentile: 0.89, width: 270, height: 120)
        #expect(curve.beatenPoints.allSatisfy { $0.x <= curve.marker.x })
        #expect(curve.beatenPoints.count < curve.outline.count)
    }

    @Test
    func anExtremePercentileStaysOnTheDrawing() {
        let top = BellCurveGeometry(percentile: 1, width: 270, height: 120)
        let bottom = BellCurveGeometry(percentile: 0, width: 270, height: 120)
        #expect(top.marker.x <= 270 && top.marker.x >= 0)
        #expect(bottom.marker.x <= 270 && bottom.marker.x >= 0)
    }
}
