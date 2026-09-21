import CoreLocation
import Testing
@testable import AscendApp

/// How pins gather into counts at world zoom and split everywhere else.
struct ClimbMapClusteringTests {
    @Test
    func atWorldZoomNearbyLandmarksBecomeOneCountAndALoneOneStaysAPin() {
        let layer = ClimbMapClustering.layer(
            for: [
                landmark(id: "esb", latitude: 40.75, longitude: -73.99),
                landmark(id: "one-wtc", latitude: 40.71, longitude: -74.01),
                landmark(id: "cn-tower", latitude: 43.64, longitude: -79.39),
                landmark(id: "burj", latitude: 25.20, longitude: 55.27),
            ],
            band: .world
        )

        #expect(layer.clusters.count == 1)
        #expect(layer.clusters.first?.count == 3)
        #expect(Set(layer.clusters.first?.landmarks.map(\.id) ?? []) == ["esb", "one-wtc", "cn-tower"])
        #expect(layer.pins.map(\.id) == ["burj"], "a cell holding one landmark is a pin, never a count of one")
    }

    @Test
    func belowWorldZoomEveryLandmarkIsItsOwnPin() {
        let landmarks = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99),
            landmark(id: "one-wtc", latitude: 40.71, longitude: -74.01),
        ]
        for band in [ClimbMapZoomBand.continent, .country, .city] {
            let layer = ClimbMapClustering.layer(for: landmarks, band: band)
            #expect(layer.clusters.isEmpty)
            #expect(layer.pins.map(\.id) == ["esb", "one-wtc"])
        }
    }

    @Test
    func aClusterIsColoredByItsHighestTierAndCheckedOnlyWhenAllAreClaimed() {
        let layer = ClimbMapClustering.layer(
            for: [
                landmark(id: "a", latitude: 40, longitude: -74, tier: .bronze, state: .completed),
                landmark(id: "b", latitude: 41, longitude: -73, tier: .epic, state: .available),
            ],
            band: .world
        )
        let cluster = layer.clusters.first
        #expect(cluster?.leadingTier == .epic)
        #expect(cluster?.isFullyCompleted == false)
    }

    @Test
    func theHighlightedLandmarkNeverHidesInsideACount() {
        let scene = AscendMapScene(
            landmarks: [
                landmark(id: "esb", latitude: 40.75, longitude: -73.99, isHighlighted: true),
                landmark(id: "one-wtc", latitude: 40.71, longitude: -74.01),
                landmark(id: "cn-tower", latitude: 43.64, longitude: -79.39),
            ],
            zoomBand: .world
        )
        let layer = scene.layer
        #expect(layer.pins.map(\.id) == ["esb"])
        #expect(layer.clusters.first?.count == 2)
    }

    @Test
    func theLegendListsOnlyTheTiersOnTheGlobeInTierOrder() {
        let scene = AscendMapScene(
            landmarks: [
                landmark(id: "a", latitude: 0, longitude: 0, tier: .mythic),
                landmark(id: "b", latitude: 1, longitude: 1, tier: .common),
                landmark(id: "c", latitude: 2, longitude: 2, tier: .mythic),
            ],
            zoomBand: .continent
        )
        #expect(scene.legendTiers == [.common, .mythic])
    }

    @Test
    func cellsAreStableUnderPanningBecauseTheyAreFixedToTheGrid() {
        let key = ClimbMapClustering.cellKey(for: CLLocationCoordinate2D(latitude: 40.75, longitude: -73.99), cellDegrees: 30)
        let sameCell = ClimbMapClustering.cellKey(for: CLLocationCoordinate2D(latitude: 43.64, longitude: -79.39), cellDegrees: 30)
        let otherCell = ClimbMapClustering.cellKey(for: CLLocationCoordinate2D(latitude: 25.20, longitude: 55.27), cellDegrees: 30)
        #expect(key == sameCell)
        #expect(key != otherCell)
    }

    // MARK: - Fixtures

    private func landmark(
        id: String,
        latitude: Double,
        longitude: Double,
        tier: ClimbTier = .gold,
        state: AscendMapLandmark.State = .available,
        isHighlighted: Bool = false
    ) -> AscendMapLandmark {
        AscendMapLandmark(
            climb: Climb(
                id: id,
                name: id,
                city: "City",
                country: "Country",
                continent: "Continent",
                latitude: latitude,
                longitude: longitude,
                totalHeightMeters: 300,
                totalHeightFeet: 984,
                realClimbableHeightMeters: nil,
                realClimbableHeightFeet: nil,
                totalSteps: 1_650,
                realStairCount: nil,
                calculatedFloors: 83,
                category: "skyscraper",
                tier: tier,
                tags: [],
                funFact: "Fact",
                sourceURL: "https://example.com"
            ),
            state: state,
            isHighlighted: isHighlighted
        )
    }
}
