import CoreLocation
import Testing
@testable import AscendApp

/// The camera bands that decide when names sit beside the markers. Clustering no
/// longer reads them; it follows overlap on screen (`ClimbMapClusteringTests`).
struct ClimbMapZoomBandTests {
    @Test(arguments: [
        (28_000_000.0, ClimbMapZoomBand.world),
        (9_000_001.0, ClimbMapZoomBand.world),
        (9_000_000.0, ClimbMapZoomBand.continent),
        (5_500_000.0, ClimbMapZoomBand.continent),
        (3_500_000.0, ClimbMapZoomBand.country),
        (2_000_000.0, ClimbMapZoomBand.country),
        (1_200_000.0, ClimbMapZoomBand.city),
        (4_000.0, ClimbMapZoomBand.city),
    ])
    func aCameraDistanceFallsInOneBand(distance: CLLocationDistance, expected: ClimbMapZoomBand) {
        #expect(ClimbMapZoomBand(cameraDistance: distance) == expected)
    }

    @Test
    func namesAppearBelowCountryZoom() {
        #expect(!ClimbMapZoomBand.world.showsNames)
        #expect(!ClimbMapZoomBand.continent.showsNames)
        #expect(ClimbMapZoomBand.country.showsNames)
        #expect(ClimbMapZoomBand.city.showsNames)
    }
}
