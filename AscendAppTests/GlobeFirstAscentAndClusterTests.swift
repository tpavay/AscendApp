import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// The dev-build fixes from 2026-09-21: the label band follows every camera move the
/// app makes itself, a cluster tap frames every member, X returns to the frame the
/// marker was tapped from, and a climb nobody has finished reads as an open First
/// Ascent once the boards have answered.
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
        #expect(viewModel.cameraZoomBand == .continent, "closing the card returns to the frame the marker was tapped from, and the names follow at once")
    }

    @Test
    func aClusterTapFliesToARegionShowingEveryMember() {
        let sanFrancisco = [
            landmark(id: "transamerica-pyramid", latitude: 37.7952, longitude: -122.4028),
            landmark(id: "salesforce-tower", latitude: 37.7897, longitude: -122.3972),
        ]
        let cluster = AscendMapCluster(id: "sf", coordinate: sanFrancisco[0].climb.coordinate, landmarks: sanFrancisco)
        let viewModel = GlobeViewModel(leaderboardService: StubLiveReplayLeaderboardService())
        viewModel.visibleClimbs = sanFrancisco.map(\.climb)

        viewModel.focusOnCluster(cluster)

        let region = try? #require(viewModel.cameraPosition.region)
        #expect(region != nil)
        if let region {
            for member in sanFrancisco {
                #expect(abs(member.climb.latitude - region.center.latitude) <= region.span.latitudeDelta / 2)
                #expect(abs(member.climb.longitude - region.center.longitude) <= region.span.longitudeDelta / 2)
            }
        }
        #expect(viewModel.cameraZoomBand == .city, "two towers in one city frame at city zoom, where names show")
    }

    @Test
    func closingTheCardRestoresTheCameraTheMarkerWasTappedFrom() throws {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = GlobeViewModel(leaderboardService: StubLiveReplayLeaderboardService())
        viewModel.visibleClimbs = [.preview]

        // The climber opened a cluster (a country-level frame), then tapped a marker in it.
        let clusterFrame = MapCamera(
            centerCoordinate: Climb.preview.coordinate,
            distance: 2_000_000,
            heading: 0,
            pitch: 0
        )
        viewModel.mapCameraDidChange(camera: clusterFrame)
        viewModel.selectPreview(.preview, modelContext: ModelContext(container))
        #expect(viewModel.cameraZoomBand == .city)

        viewModel.dismissPreview()

        let restored = try #require(viewModel.cameraPosition.camera)
        #expect(restored.distance == clusterFrame.distance)
        #expect(abs(restored.centerCoordinate.latitude - clusterFrame.centerCoordinate.latitude) < 0.0001)
        #expect(viewModel.cameraZoomBand == .country, "the names follow the restored frame without a touch")
    }

    @Test
    func closingTheCardWithNoRememberedFrameReturnsToTheGlobe() throws {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = GlobeViewModel(leaderboardService: StubLiveReplayLeaderboardService())
        viewModel.visibleClimbs = [.preview]

        viewModel.selectPreview(.preview, modelContext: ModelContext(container))
        viewModel.dismissPreview()

        #expect(viewModel.cameraZoomBand == .world)
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
