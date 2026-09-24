import Foundation
import SwiftData
import Testing
import UIKit

@testable import AscendApp

/// How a live session gets its progress cut-out: the photo layout until the image is in hand,
/// the landmark layout once it lands - mid-climb if need be - and the photo layout for good if it
/// never does. The session itself never waits on it.
@MainActor
struct LiveClimbSessionProgressArtworkTests {
    @Test("While the cut-out loads the session records normally, and it switches in when it lands")
    func cutOutArrivesMidClimbWithoutDisturbingTheSession() async throws {
        let repository = GatedClimbProgressImageRepository()
        let (viewModel, motionSession, _) = try Self.startedSession(climbID: "charminar", repository: repository)

        let loading = Task { await viewModel.loadProgressArtworkIfNeeded() }
        try await Self.waitUntil { repository.hasPendingRequest }
        #expect(viewModel.progressArtwork == nil, "no cut-out yet: the tab shows its photo layout")

        motionSession.stepCount = 60
        motionSession.duration = 45
        #expect(viewModel.isRecording)
        #expect(viewModel.totalRecordedSteps == 60)

        repository.release(with: try Self.fixtureImage("charminar"))
        await loading.value

        let loaded = try #require(viewModel.progressArtwork)
        #expect(loaded.artwork.path == "climb-images/charminar/progress/v1.png")
        #expect(viewModel.isRecording, "the cut-out's arrival does not touch the session")
        #expect(viewModel.totalRecordedSteps == 60)
        #expect(viewModel.elapsedClock == "0:45")
    }

    @Test("A failed fetch leaves the photo layout in place, and the next attempt tries again")
    func failedFetchFallsBackAndRetries() async throws {
        let repository = GatedClimbProgressImageRepository()
        let (viewModel, _, _) = try Self.startedSession(climbID: "eiffel-tower", repository: repository)

        let firstAttempt = Task { await viewModel.loadProgressArtworkIfNeeded() }
        try await Self.waitUntil { repository.hasPendingRequest }
        repository.release(with: nil)
        await firstAttempt.value
        #expect(viewModel.progressArtwork == nil)
        #expect(viewModel.isRecording)

        let secondAttempt = Task { await viewModel.loadProgressArtworkIfNeeded() }
        try await Self.waitUntil { repository.hasPendingRequest }
        #expect(repository.requestCount == 2)
        repository.release(with: try Self.fixtureImage("eiffel-tower"))
        await secondAttempt.value
        #expect(viewModel.progressArtwork != nil)
    }

    @Test("Once loaded, the cut-out is never fetched again for the session")
    func loadedCutOutIsNotRefetched() async throws {
        let (viewModel, _, _) = try Self.startedSession(climbID: "empire-state-building", repository: FixtureClimbProgressImageRepository())
        await viewModel.loadProgressArtworkIfNeeded()
        let first = try #require(viewModel.progressArtwork)
        await viewModel.loadProgressArtworkIfNeeded()
        #expect(viewModel.progressArtwork == first)
    }

    @Test("A climb whose entry has no cut-out never asks for one")
    func climbWithoutACutOutNeverFetches() async throws {
        let repository = GatedClimbProgressImageRepository()
        let (viewModel, _, _) = try Self.startedSession(climbID: "the-shard", repository: repository)

        await viewModel.loadProgressArtworkIfNeeded()
        #expect(viewModel.progressArtwork == nil)
        #expect(repository.requestCount == 0)
    }

    @Test("An entry pointing outside its climb's folder is never fetched")
    func unusableEntryIsNeverFetched() async throws {
        let base = try #require(BundledClimbCatalog.climbs.first { $0.id == "charminar" })
        let artwork = try #require(base.progressArtwork)
        let climb = Self.climb(base, progressArtwork: ClimbProgressArtwork(
            path: "climb-images/eiffel-tower/progress/v1.png",
            canvasWidth: artwork.canvasWidth,
            canvasHeight: artwork.canvasHeight,
            visibleBoundsPixels: artwork.visibleBoundsPixels,
            progressTopY: artwork.progressTopY,
            progressBottomY: artwork.progressBottomY
        ))
        let repository = GatedClimbProgressImageRepository()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            progressImageRepository: repository
        )

        await viewModel.loadProgressArtworkIfNeeded()
        #expect(viewModel.progressArtwork == nil)
        #expect(repository.requestCount == 0)
    }

    @Test("A restored session gets its cut-out the same way a fresh one does")
    func restoredSessionLoadsItsCutOut() async throws {
        let climb = try #require(BundledClimbCatalog.climbs.first { $0.id == "charminar" })
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "progress-artwork-restore",
            kind: .liveClimb,
            startedAt: Date(timeIntervalSinceNow: -120),
            title: climb.name,
            subtitle: climb.displayLocation,
            workoutName: "\(climb.name) Live Climb",
            targetStepCount: climb.referenceStepCount,
            targetDurationSeconds: nil
        )
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            recoveredDraft: draft,
            progressImageRepository: FixtureClimbProgressImageRepository()
        )

        await viewModel.loadProgressArtworkIfNeeded()
        #expect(viewModel.progressArtwork?.artwork.path == "climb-images/charminar/progress/v1.png")
    }

    // MARK: - Fixtures

    private static func startedSession(
        climbID: String,
        repository: any ClimbProgressImageRepository
    ) throws -> (LiveClimbSessionViewModel, FakeHeadphoneMotionSession, ModelContainer) {
        let climb = try #require(BundledClimbCatalog.climbs.first { $0.id == climbID })
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            progressImageRepository: repository
        )
        viewModel.start(modelContext: container.mainContext)
        motionSession.status = .recording
        return (viewModel, motionSession, container)
    }

    private static func fixtureImage(_ climbID: String) throws -> UIImage {
        try #require(UIImage(contentsOfFile: FixtureClimbProgressImageRepository.fixtureURL(forClimbID: climbID).path(percentEncoded: false)))
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition never held")
    }

    private static func climb(_ base: Climb, progressArtwork: ClimbProgressArtwork) -> Climb {
        Climb(
            id: base.id, name: base.name, city: base.city, country: base.country, continent: base.continent,
            latitude: base.latitude, longitude: base.longitude,
            totalHeightMeters: base.totalHeightMeters, totalHeightFeet: base.totalHeightFeet,
            realClimbableHeightMeters: base.realClimbableHeightMeters, realClimbableHeightFeet: base.realClimbableHeightFeet,
            totalSteps: base.totalSteps, realStairCount: base.realStairCount, calculatedFloors: base.calculatedFloors,
            category: base.category, tier: base.tier, tags: base.tags, funFact: base.funFact, sourceURL: base.sourceURL,
            imageSetVersion: base.imageSetVersion, releaseState: base.releaseState, progressArtwork: progressArtwork
        )
    }
}
