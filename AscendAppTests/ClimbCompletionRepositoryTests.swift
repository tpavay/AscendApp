import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct ClimbCompletionRepositoryTests {
    private let userId = "user-1"
    private let stagingClimbIds = [
        "marina-bay-sands",
        "empire-state-building",
        "burj-khalifa",
        "sagrada-familia",
        "cn-tower",
    ]

    // Test 1: the globe reads a server-authoritative 5 through the repository.
    @Test
    func repositoryReadsServerAuthoritativeFive() async throws {
        let context = try makeContext()
        let remote = StubRemote(results: stagingClimbIds.map(landmarkResult(climbId:)))
        let repository = ClimbCompletionRepository(remoteRepository: remote)

        let set = await repository.refresh(userId: userId, modelContext: context)

        #expect(set.completedCount == 5)
        #expect(repository.read(modelContext: context).completedCount == 5)
        #expect(HomeDashboardViewModel.fetchCompletedClimbCount(modelContext: context) == 5)
    }

    // Test 2: an in-place UPDATE (short local cache, no fresh hydration) still
    // shows 5 after refresh. The contrast proves the fix is the server read: the
    // same short cache read directly returns 1.
    @Test
    func inPlaceUpdateHealsShortCacheToFive() async throws {
        let context = try makeContext()
        // The old guard left only CN Tower in the cache; an app-store update
        // keeps that local store and never re-hydrates.
        context.insert(completedAttempt(climbId: "cn-tower"))
        try context.save()

        // Reading the cache directly (no repository) returns the stale 1.
        #expect(
            ClimbCompletionRepository.completedClimbSet(modelContext: context).completedCount == 1
        )

        let remote = StubRemote(results: stagingClimbIds.map(landmarkResult(climbId:)))
        let repository = ClimbCompletionRepository(remoteRepository: remote)
        let set = await repository.refresh(userId: userId, modelContext: context)

        #expect(set.completedCount == 5)
    }

    // Test 3: the three completion surfaces agree by construction - all read the
    // one distinct-climb set. Includes the divergence regression: a climb
    // completed three times is 1 everywhere, not "globe 1, aggregate 3".
    @Test
    func threeSurfacesAgreeAndThreeCompletionsCollapseToOne() throws {
        let context = try makeContext()
        // Three completed attempts of ONE climb, plus one of another.
        context.insert(completedAttempt(climbId: "cn-tower"))
        context.insert(completedAttempt(climbId: "cn-tower"))
        context.insert(completedAttempt(climbId: "cn-tower"))
        context.insert(completedAttempt(climbId: "empire-state-building"))
        try context.save()

        let attempts = try context.fetch(FetchDescriptor<ClimbAttempt>())
        let set = ClimbCompletionRepository.completedClimbSet(from: attempts)
        let catalog = [climb(id: "cn-tower"), climb(id: "empire-state-building")]

        let globeNumerator = HomeDashboardViewModel
            .fetchCompletedClimbCount(modelContext: context)
        let stats = ProfileSnapshotBuilder.statsSnapshot(
            workouts: [],
            completedAttempts: attempts,
            completedCount: set.completedCount,
            achievements: .zero
        )
        let snapshot = ProfileSnapshotBuilder.makeOwnSnapshot(
            identity: ProfileUserIdentity(userId: userId, displayName: "Tester"),
            workouts: [],
            climbAttempts: attempts,
            completedClimbSet: set,
            bestEffortCacheEntries: [],
            achievements: .zero,
            standings: [],
            climbs: catalog,
            fitnessLevel: .beginner
        )

        #expect(set.completedCount == 2)
        #expect(globeNumerator == 2)
        #expect(stats.totalClimbsCompleted == 2)
        #expect(snapshot.collection.collectedCount == 2)

        // The three-completion climb is a single claimed landmark.
        #expect(set.climbs.first { $0.climbId == "cn-tower" }?.attemptCount == 3)
    }

    // Test 4: durability round-trip. With NO local attempt, refresh pulls the
    // completion from the server projection; wiping the cache and refreshing
    // again restores it - zero dependence on local reconstruction.
    @Test
    func durabilityRoundTripFromProjectionOnly() async throws {
        let context = try makeContext()
        let remote = StubRemote(results: [landmarkResult(climbId: "burj-khalifa")])
        let repository = ClimbCompletionRepository(remoteRepository: remote)

        let set = await repository.refresh(userId: userId, modelContext: context)
        #expect(set.completedClimbIds == ["burj-khalifa"])

        // Wipe the cache, then refresh again: the projection restores it.
        for attempt in try context.fetch(FetchDescriptor<ClimbAttempt>()) {
            context.delete(attempt)
        }
        try context.save()
        #expect(repository.read(modelContext: context).completedCount == 0)

        let restored = await repository.refresh(userId: userId, modelContext: context)
        #expect(restored.completedClimbIds == ["burj-khalifa"])
    }

    // Reconcile is idempotent: refreshing twice never duplicates the cache row.
    @Test
    func refreshIsIdempotent() async throws {
        let context = try makeContext()
        let remote = StubRemote(results: stagingClimbIds.map(landmarkResult(climbId:)))
        let repository = ClimbCompletionRepository(remoteRepository: remote)

        _ = await repository.refresh(userId: userId, modelContext: context)
        let afterFirst = try context.fetch(FetchDescriptor<ClimbAttempt>()).count
        _ = await repository.refresh(userId: userId, modelContext: context)
        let afterSecond = try context.fetch(FetchDescriptor<ClimbAttempt>()).count

        #expect(afterFirst == 5)
        #expect(afterSecond == 5)
    }

    // A climb rebuilt purely from the projection reports the FIRST completion as
    // its claim date, not the latest. The reconcile row collapses first/latest
    // into one attempt, so the read must resolve `firstCompletedAt` back to the
    // projection's `firstCompletedAt` for Collection `claimedAt` to be correct.
    @Test
    func projectionMaterializedClimbClaimsFirstCompletion() async throws {
        let context = try makeContext()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let latest = Date(timeIntervalSince1970: 1_700_000_600)
        let remote = StubRemote(results: [
            RemoteLandmarkResult(
                climbId: "burj-khalifa",
                completed: true,
                firstCompletedAt: first,
                latestCompletedAt: latest,
                attemptCount: 3,
                bestWorkoutId: nil,
                bestElapsedSeconds: 600
            )
        ])
        let repository = ClimbCompletionRepository(remoteRepository: remote)

        let set = await repository.refresh(userId: userId, modelContext: context)

        let completed = try #require(set.climbs.first { $0.climbId == "burj-khalifa" })
        #expect(completed.firstCompletedAt == first)
        #expect(completed.latestCompletedAt == latest)
    }

    // Test 6 (FA integrity): a materialized completion never carries a First
    // Ascent - the repository writes no globalCompletionOrder. First Ascent
    // stays owned by the replay path.
    @Test
    func materializedCompletionNeverClaimsFirstAscent() async throws {
        let context = try makeContext()
        let remote = StubRemote(results: [landmarkResult(climbId: "cn-tower")])
        let repository = ClimbCompletionRepository(remoteRepository: remote)

        _ = await repository.refresh(userId: userId, modelContext: context)

        let attempts = try context.fetch(FetchDescriptor<ClimbAttempt>())
        #expect(attempts.count == 1)
        #expect(attempts.allSatisfy { $0.globalCompletionOrder == nil })
    }

    // A transient/offline read keeps serving the cache - never drops earned
    // completions to a smaller number.
    @Test
    func offlineRefreshKeepsExistingCache() async throws {
        let context = try makeContext()
        context.insert(completedAttempt(climbId: "cn-tower"))
        try context.save()

        let repository = ClimbCompletionRepository(remoteRepository: FailingRemote())
        let set = await repository.refresh(userId: userId, modelContext: context)

        #expect(set.completedClimbIds == ["cn-tower"])
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClimbAttempt.self,
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func landmarkResult(climbId: String) -> RemoteLandmarkResult {
        RemoteLandmarkResult(
            climbId: climbId,
            completed: true,
            firstCompletedAt: Date(timeIntervalSince1970: 1_700_000_000),
            latestCompletedAt: Date(timeIntervalSince1970: 1_700_000_600),
            attemptCount: 1,
            bestWorkoutId: nil,
            bestElapsedSeconds: 600
        )
    }

    private func completedAttempt(climbId: String) -> ClimbAttempt {
        ClimbAttempt(
            climbId: climbId,
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            completedAt: Date(timeIntervalSince1970: 1_700_000_600),
            accumulatedSteps: 1_000,
            accumulatedDurationSeconds: 600,
            sessionsCount: 1
        )
    }

    private func climb(id: String) -> Climb {
        Climb(
            id: id,
            name: id,
            city: "City",
            country: "Country",
            continent: "Continent",
            latitude: 0,
            longitude: 0,
            totalHeightMeters: 100,
            totalHeightFeet: 328,
            realClimbableHeightMeters: nil,
            realClimbableHeightFeet: nil,
            totalSteps: 1_000,
            realStairCount: nil,
            calculatedFloors: 50,
            category: "tower",
            tier: .common,
            tags: [],
            funFact: "Test climb",
            sourceURL: "https://example.com",
            releaseState: .available
        )
    }
}

private struct StubRemote: ClimbCompletionRemoteRepositoryProtocol {
    let results: [RemoteLandmarkResult]

    func fetchLandmarkResults(userId: String) async throws -> [RemoteLandmarkResult] {
        results
    }
}

private struct FailingRemote: ClimbCompletionRemoteRepositoryProtocol {
    struct Offline: Error {}

    func fetchLandmarkResults(userId: String) async throws -> [RemoteLandmarkResult] {
        throw Offline()
    }
}
