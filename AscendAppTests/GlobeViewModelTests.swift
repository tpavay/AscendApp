//
//  GlobeViewModelTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/6/26.
//

import CoreLocation
import MapKit
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct GlobeViewModelTests {
    @Test
    func compactLandmarksUseTighterPreviewZoomThanLargeNaturalClimbs() {
        let gatewayArch = makeClimb(
            id: "gateway-arch",
            category: "monument",
            heightMeters: 192,
            steps: 1_056,
            floors: 53
        )
        let machuPicchu = makeClimb(
            id: "machu-picchu",
            category: "fortress",
            heightMeters: 2_430,
            steps: 13_365,
            floors: 675
        )
        let matterhorn = makeClimb(
            id: "matterhorn",
            category: "mountain",
            heightMeters: 4_478,
            steps: 24_629,
            floors: 1_244
        )

        #expect(gatewayArch.browsePreviewCameraDistance < machuPicchu.browsePreviewCameraDistance)
        #expect(machuPicchu.browsePreviewCameraDistance < matterhorn.browsePreviewCameraDistance)
        #expect((180_000.0...850_000.0).contains(gatewayArch.browsePreviewCameraDistance))
        #expect((320_000.0...1_500_000.0).contains(machuPicchu.browsePreviewCameraDistance))
        #expect((1_100_000.0...3_000_000.0).contains(matterhorn.browsePreviewCameraDistance))
    }

    @Test
    func selectPreviewUsesClimbSpecificFlyoverDistance() throws {
        let climb = makeClimb(
            id: "gateway-arch",
            latitude: 38.6247,
            longitude: -90.1848,
            category: "monument",
            heightMeters: 192,
            steps: 1_056,
            floors: 53
        )
        let viewModel = GlobeViewModel(climbService: makeClimbService(with: [climb]))
        let modelContext = try makeModelContext()

        viewModel.selectPreview(climb, modelContext: modelContext)

        let camera = try #require(viewModel.cameraPosition.camera)
        #expect(viewModel.previewSummary?.climb.id == climb.id)
        #expect(camera.distance == ClimbCameraFraming.distance(for: climb))
        #expect(camera.centerCoordinate.latitude == climb.latitude)
        #expect(camera.centerCoordinate.longitude == climb.longitude)
    }

    @Test
    func prepareForBrowseEntryClearsPreviewAndRestoresDefaultOverview() throws {
        let climb = makeClimb(
            id: "empire-state-building",
            latitude: 40.7484,
            longitude: -73.9857,
            category: "skyscraper",
            heightMeters: 381,
            steps: 2_096,
            floors: 106
        )
        let viewModel = GlobeViewModel(climbService: makeClimbService(with: [climb]))
        let modelContext = try makeModelContext()

        viewModel.searchQuery = "Empire"
        viewModel.selectPreview(climb, modelContext: modelContext)
        viewModel.prepareForBrowseEntry()

        let camera = try #require(viewModel.cameraPosition.camera)
        #expect(viewModel.searchQuery.isEmpty)
        #expect(viewModel.previewSummary == nil)
        #expect(camera.distance == 28_000_000)
        #expect(camera.centerCoordinate.latitude == 18.0)
        #expect(camera.centerCoordinate.longitude == 8.0)
    }

    @Test
    func dismissPreviewRestoresOverviewZoomAtCurrentCenter() throws {
        let climb = makeClimb(
            id: "gateway-arch",
            latitude: 38.6247,
            longitude: -90.1848,
            category: "monument",
            heightMeters: 192,
            steps: 1_056,
            floors: 53
        )
        let viewModel = GlobeViewModel(climbService: makeClimbService(with: [climb]))
        let modelContext = try makeModelContext()

        viewModel.selectPreview(climb, modelContext: modelContext)
        viewModel.mapCameraDidChange(latitude: 12.34, longitude: 56.78)
        viewModel.dismissPreview()

        let camera = try #require(viewModel.cameraPosition.camera)
        #expect(viewModel.previewSummary == nil)
        #expect(camera.distance == 28_000_000)
        #expect(camera.centerCoordinate.latitude == 12.34)
        #expect(camera.centerCoordinate.longitude == 56.78)
    }

    @Test
    func liveClimbCommunityLoadsGlobalCompletedUserSummary() async throws {
        let climb = makeClimb(
            id: "pyramid-giza",
            category: "monument",
            heightMeters: 138,
            steps: 809,
            floors: 41
        )
        let communityStatsService = StaticLiveClimbCommunityStatsService(
            summary: LiveClimbCommunitySummary(
                uniqueCompletedUserCount: 247,
                updatedAt: Date(timeIntervalSince1970: 1_777_777_700)
            )
        )
        let viewModel = GlobeViewModel(
            climbService: makeClimbService(with: [climb]),
            communityStatsService: communityStatsService
        )
        let modelContext = try makeModelContext()

        viewModel.loadIfNeeded(modelContext: modelContext)
        await viewModel.refreshLiveClimbCommunityStats()

        #expect(viewModel.liveClimbCommunityCompletedUserCount == 247)
        #expect(await communityStatsService.fetchCount == 1)
    }

    @Test
    func liveClimbCommunityFallsBackToLocalCompletedUser() {
        let climb = makeClimb(
            id: "gateway-arch",
            category: "monument",
            heightMeters: 192,
            steps: 1_056,
            floors: 53
        )
        let viewModel = GlobeViewModel(climbService: makeClimbService(with: [climb]))

        viewModel.visibleClimbs = [climb]
        viewModel.completedClimbIds = [climb.id]

        #expect(viewModel.liveClimbCommunityCompletedUserCount == 1)
    }

    @Test
    func comingSoonClimbsStayOnGlobeButOutOfSearchAndDailyRecommendation() throws {
        let available = makeClimb(
            id: "available-climb",
            category: "tower",
            heightMeters: 100,
            steps: 1_000,
            floors: 50
        )
        let comingSoon = makeClimb(
            id: "coming-soon-climb",
            category: "tower",
            heightMeters: 200,
            steps: 2_000,
            floors: 100,
            releaseState: .comingSoon
        )
        let viewModel = GlobeViewModel(climbService: makeClimbService(with: [available, comingSoon]))
        let modelContext = try makeModelContext()

        GlobeViewModel.debugClearDailyRecommendedClimbId()
        viewModel.loadIfNeeded(modelContext: modelContext)
        viewModel.searchQuery = "coming"

        #expect(viewModel.visibleClimbs.map(\.id) == [available.id, comingSoon.id])
        #expect(viewModel.availableClimbs.map(\.id) == [available.id])
        #expect(viewModel.searchSuggestions.isEmpty)
        #expect(viewModel.dailyRecommendedClimb?.id == available.id)
    }


    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClimbAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeClimbService(with climbs: [Climb]) -> ClimbService {
        ClimbService(catalogRepository: StaticClimbCatalogRepository(climbs: climbs))
    }

    private func makeClimb(
        id: String,
        latitude: Double = 0,
        longitude: Double = 0,
        category: String,
        heightMeters: Double,
        steps: Int,
        floors: Int,
        releaseState: ClimbReleaseState = .available
    ) -> Climb {
        Climb(
            id: id,
            name: id,
            city: "City",
            country: "Country",
            continent: "Continent",
            latitude: latitude,
            longitude: longitude,
            totalHeightMeters: heightMeters,
            totalHeightFeet: heightMeters * 3.28084,
            realClimbableHeightMeters: nil,
            realClimbableHeightFeet: nil,
            totalSteps: steps,
            realStairCount: nil,
            calculatedFloors: floors,
            category: category,
            tier: .gold,
            tags: [],
            funFact: "Fact",
            sourceURL: "https://example.com",
            imageSetVersion: 1,
            releaseState: releaseState
        )
    }
}

private actor StaticLiveClimbCommunityStatsService: LiveClimbCommunityStatsServicing {
    private let summary: LiveClimbCommunitySummary
    private(set) var fetchCount = 0

    init(summary: LiveClimbCommunitySummary) {
        self.summary = summary
    }

    func fetchSummary() async throws -> LiveClimbCommunitySummary {
        fetchCount += 1
        return summary
    }
}

private struct StaticClimbCatalogRepository: ClimbCatalogRepository {
    let climbs: [Climb]

    func loadInitialCatalog() throws -> ClimbCatalogSnapshot {
        ClimbCatalogSnapshot(
            climbs: climbs,
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: climbs.first?.id,
            updatedAt: nil
        )
    }

    func refreshCatalog() async throws -> ClimbCatalogSnapshot {
        try loadInitialCatalog()
    }
}
