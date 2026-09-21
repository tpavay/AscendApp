import CoreLocation
import MapKit
import SwiftData
import Testing
@testable import AscendApp

/// The dev-build fixes from 2026-09-21: the pin layer follows every camera move the
/// app makes itself, a cluster tap lands where its members split apart, and a climb
/// nobody has finished reads as an open First Ascent once the boards have answered.
@MainActor
struct GlobeFirstAscentAndClusterTests {
    @Test
    func aProgrammaticCameraMoveUpdatesTheBandWithoutATouch() throws {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = GlobeViewModel(leaderboardService: StubLiveReplayLeaderboardService())
        viewModel.visibleClimbs = [.preview]
        viewModel.dailyRecommendedClimb = .preview

        viewModel.prepareForHomeEntry()
        #expect(viewModel.cameraZoomBand == .continent)

        viewModel.selectPreview(.preview, modelContext: ModelContext(container))
        #expect(viewModel.cameraZoomBand == .city, "the pin fly-in is a city-altitude framing")

        viewModel.dismissPreview()
        #expect(viewModel.cameraZoomBand == .world, "closing the card zooms out, and the counts redraw at once")
    }

    @Test
    func aClusterOfTowersInOneCityZoomsToTheCity() {
        let sanFrancisco = [
            landmark(id: "transamerica-pyramid", latitude: 37.7952, longitude: -122.4028),
            landmark(id: "salesforce-tower", latitude: 37.7897, longitude: -122.3972),
        ]
        let cluster = AscendMapCluster(id: "sf", coordinate: sanFrancisco[0].climb.coordinate, landmarks: sanFrancisco)

        let distance = GlobeViewModel.clusterFocusDistance(for: cluster, from: .world)

        #expect(ClimbMapZoomBand(cameraDistance: distance) == .city)
        #expect(!ClimbMapZoomBand(cameraDistance: distance).clustersPins)
    }

    @Test
    func aContinentWideClusterZoomsOneBandIn() {
        let spread = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99),
            landmark(id: "cn-tower", latitude: 43.64, longitude: -79.39),
            landmark(id: "space-needle", latitude: 47.62, longitude: -122.35),
        ]
        let cluster = AscendMapCluster(id: "na", coordinate: spread[0].climb.coordinate, landmarks: spread)

        #expect(GlobeViewModel.clusterFocusDistance(for: cluster, from: .world) == ClimbMapZoomBand.world.clusterFocusDistance)

        let country = [
            landmark(id: "esb", latitude: 40.75, longitude: -73.99),
            landmark(id: "one-liberty", latitude: 39.95, longitude: -75.16),
        ]
        let countryCluster = AscendMapCluster(id: "ne", coordinate: country[0].climb.coordinate, landmarks: country)
        #expect(ClimbMapZoomBand(cameraDistance: GlobeViewModel.clusterFocusDistance(for: countryCluster, from: .world)) == .country)
    }

    @Test
    func markersCarryTheFinisherCountOnlyOnceTheBoardsAnswered() async {
        let service = StubLiveReplayLeaderboardService()
        service.completedClimberCounts = ["empire-state-building": 12]
        let viewModel = GlobeViewModel(leaderboardService: service)
        let open = landmark(id: "sky-tower", latitude: -36.85, longitude: 174.76).climb
        viewModel.visibleClimbs = [.preview, open]

        // Unread: no count and no open claim, so the globe never promises what it has not checked.
        #expect(viewModel.completedClimberCount(for: open) == nil)
        #expect(!viewModel.isFirstAscentOpen(open))
        #expect(viewModel.mapScene.landmarks.allSatisfy { $0.state == .available && $0.completedClimberCount == nil })

        await viewModel.refreshCompletedClimberCounts()

        #expect(viewModel.completedClimberCount(for: .preview) == 12)
        #expect(viewModel.completedClimberCount(for: open) == 0, "a landmark with no board has no finisher")
        #expect(viewModel.isFirstAscentOpen(open))
        #expect(!viewModel.isFirstAscentOpen(.preview), "a claimed board is not open")
        let byId = Dictionary(uniqueKeysWithValues: viewModel.mapScene.landmarks.map { ($0.id, $0) })
        #expect(byId["sky-tower"]?.state == .firstAscentOpen)
        #expect(byId[Climb.preview.id]?.state == .available)
        #expect(byId[Climb.preview.id]?.completedClimberCount == 12)
        #expect(!viewModel.isFirstAscentOpen(.previewComingSoon), "a coming-soon climb cannot be claimed yet")
    }

    @Test
    func theCardReadsTheSameCountAsTheMarker() async throws {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = StubLiveReplayLeaderboardService()
        service.completedClimberCounts = ["empire-state-building": 12]
        let viewModel = GlobeViewModel(leaderboardService: service)
        viewModel.visibleClimbs = [.preview]
        await viewModel.refreshCompletedClimberCounts()

        viewModel.selectPreview(.preview, modelContext: ModelContext(container))

        #expect(viewModel.previewCompletedClimberCount == 12)
        #expect(viewModel.mapScene.landmarks.first?.completedClimberCount == 12)
    }

    @Test(arguments: [(1, "1"), (999, "999"), (1_000, "1k"), (1_250, "1.3k"), (12_400, "12.4k")])
    func aMarkerCompressesThousands(count: Int, expected: String) {
        #expect(ClimbMarkerView.countText(count) == expected)
    }

    private func landmark(id: String, latitude: Double, longitude: Double) -> AscendMapLandmark {
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
                tier: .gold,
                tags: [],
                funFact: "Fact",
                sourceURL: "https://example.com"
            ),
            state: .available,
            isHighlighted: false
        )
    }
}
