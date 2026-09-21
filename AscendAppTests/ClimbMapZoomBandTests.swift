import CoreLocation
import Testing
@testable import AscendApp

/// The thresholds that decide when the globe clusters, names and gains streets. The
/// map reads a band, never a raw distance, so these are the whole contract.
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
    func onlyWorldZoomClustersAndCountsSplitOnTheWayIn() {
        #expect(ClimbMapZoomBand.world.clustersPins)
        #expect(!ClimbMapZoomBand.continent.clustersPins)
        #expect(!ClimbMapZoomBand.country.clustersPins)
        #expect(!ClimbMapZoomBand.city.clustersPins)
    }

    @Test
    func namesAppearBelowCountryZoomAndStreetsAtCityZoom() {
        #expect(!ClimbMapZoomBand.world.showsNames)
        #expect(!ClimbMapZoomBand.continent.showsNames)
        #expect(ClimbMapZoomBand.country.showsNames)
        #expect(ClimbMapZoomBand.city.showsNames)

        #expect(ClimbMapZoomBand.allCases.filter(\.showsStreets) == [.city])
    }

    @Test
    func homeOpensAtContinentAltitude() {
        #expect(ClimbMapZoomBand(cameraDistance: ClimbMapZoomBand.homeEntryCameraDistance) == .continent)
    }

    @Test
    func tappingAClusterFliesInsideTheNextBand() {
        let focused = ClimbMapZoomBand(cameraDistance: ClimbMapZoomBand.world.clusterFocusDistance)
        #expect(focused == .continent, "a world cluster opens onto the continent, where its members split")
        #expect(!focused.clustersPins)
    }
}
