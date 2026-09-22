import CoreGraphics
import CoreLocation
import MapKit
import Testing
@testable import AscendApp

/// Overlap-driven clustering: markers gather into one pill only while their dots would
/// sit on top of each other on screen, and dissolve the moment they separate.
struct ClimbMapClusteringTests {
    @Test
    func dotsThatWouldOverlapBecomeOnePillAndSeparatedOnesStayDots() {
        let landmarks = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99),
            landmark(id: "one-wtc", latitude: 40.71, longitude: -74.01),
            landmark(id: "chrysler", latitude: 40.75, longitude: -73.98),
            landmark(id: "cn-tower", latitude: 43.64, longitude: -79.39),
        ]
        let worldZoomPoints: [String: CGPoint] = [
            "esb": CGPoint(x: 200, y: 300),
            "one-wtc": CGPoint(x: 204, y: 306),
            "chrysler": CGPoint(x: 210, y: 298),
            "cn-tower": CGPoint(x: 150, y: 260),
        ]

        let layer = ClimbMapClustering.layer(for: landmarks, points: worldZoomPoints)

        #expect(layer.clusters.count == 1)
        #expect(Set(layer.clusters.first?.landmarks.map(\.id) ?? []) == ["esb", "one-wtc", "chrysler"])
        #expect(layer.pins.map(\.id) == ["cn-tower"], "a lone landmark is its own dot at every zoom")
    }

    @Test
    func thePillDissolvesAsSoonAsTheDotsSeparate() {
        let landmarks = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99),
            landmark(id: "one-wtc", latitude: 40.71, longitude: -74.01),
        ]
        let apart: [String: CGPoint] = [
            "esb": CGPoint(x: 200, y: 300),
            "one-wtc": CGPoint(x: 200 + ClimbMapClustering.overlapDistance + 1, y: 300),
        ]

        let layer = ClimbMapClustering.layer(for: landmarks, points: apart)

        #expect(layer.clusters.isEmpty)
        #expect(layer.pins.map(\.id) == ["esb", "one-wtc"])
    }

    @Test
    func aChainOfOverlapsIsOneGroup() {
        let landmarks = (0..<4).map { landmark(id: "l\($0)", latitude: 0, longitude: Double($0)) }
        // Each dot overlaps only its neighbour; the chain still reads as one pill.
        let points = Dictionary(uniqueKeysWithValues: (0..<4).map {
            ("l\($0)", CGPoint(x: 100 + CGFloat($0) * (ClimbMapClustering.overlapDistance - 2), y: 100))
        })

        let layer = ClimbMapClustering.layer(for: landmarks, points: points)

        #expect(layer.clusters.count == 1)
        #expect(layer.clusters.first?.count == 4)
    }

    @Test
    func theHighlightedLandmarkNeverHidesInsideAPill() {
        let landmarks = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99, isHighlighted: true),
            landmark(id: "one-wtc", latitude: 40.71, longitude: -74.01),
            landmark(id: "chrysler", latitude: 40.75, longitude: -73.98),
        ]
        let points: [String: CGPoint] = [
            "esb": CGPoint(x: 200, y: 300),
            "one-wtc": CGPoint(x: 204, y: 306),
            "chrysler": CGPoint(x: 210, y: 298),
        ]

        let layer = ClimbMapClustering.layer(for: landmarks, points: points)

        #expect(layer.pins.map(\.id) == ["esb"])
        #expect(layer.clusters.first?.count == 2)
    }

    @Test
    func anUnprojectedLandmarkIsDrawnOnItsOwn() {
        let landmarks = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99),
            landmark(id: "far-side", latitude: -40, longitude: 106),
        ]
        let layer = ClimbMapClustering.layer(for: landmarks, points: ["esb": CGPoint(x: 10, y: 10)])

        #expect(layer.pins.map(\.id).sorted() == ["esb", "far-side"])
        #expect(layer.clusters.isEmpty)
    }

    @Test
    func aClusterIsColoredByItsHighestTierAndCheckedOnlyWhenAllAreClaimed() {
        let layer = ClimbMapClustering.layer(
            for: [
                landmark(id: "a", latitude: 40, longitude: -74, tier: .bronze, state: .completed),
                landmark(id: "b", latitude: 41, longitude: -73, tier: .epic, state: .available),
            ],
            points: ["a": CGPoint(x: 0, y: 0), "b": CGPoint(x: 4, y: 4)]
        )
        let cluster = layer.clusters.first
        #expect(cluster?.leadingTier == .epic)
        #expect(cluster?.isFullyCompleted == false)
    }

    @Test
    func theRegionForAClusterShowsEveryMemberWithRoomToSeparate() {
        let cluster = AscendMapCluster(
            id: "sf",
            coordinate: CLLocationCoordinate2D(latitude: 37.79, longitude: -122.40),
            landmarks: [
                landmark(id: "transamerica-pyramid", latitude: 37.7952, longitude: -122.4028),
                landmark(id: "salesforce-tower", latitude: 37.7897, longitude: -122.3972),
            ]
        )

        let region = ClimbMapClustering.region(showing: cluster)

        for member in cluster.landmarks {
            #expect(abs(member.climb.latitude - region.center.latitude) <= region.span.latitudeDelta / 2)
            #expect(abs(member.climb.longitude - region.center.longitude) <= region.span.longitudeDelta / 2)
        }
        #expect(region.span.latitudeDelta >= 0.02, "never tighter than a city block")
        #expect(region.span.latitudeDelta < 0.1, "and never a whole state for two towers on one street")
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
