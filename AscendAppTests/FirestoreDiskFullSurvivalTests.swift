import FirebaseFirestore
import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// The regression test for the 2026-10-23 production crash, on the real code and the real SDK.
///
/// Before the guard, the first test here aborted the host inside
/// `firebase::firestore::local::LevelDbTransaction::Commit()` with `No space left on device`
/// on the fifth-or-so live-leaderboard read after the volume filled - the evidence is in the
/// pull request that added it. Ascend now ships the memory cache, which the second test holds;
/// the first holds the pre-flight that still guards a process the kill switch put on the
/// persistent cache: the same sequence must leave it alive, the session recording, and the
/// board saying it could not refresh.
///
/// Needs the APFS image `scripts/ci/run-ios-test-passes.sh` attaches; without it the suite
/// skips itself and says so, and in CI it is a named pass that must execute.
@Suite(
    .serialized,
    .disabled(
        if: FirestoreDiskFullLab.mountPoint == nil,
        "needs ASCEND_DISKFULL_MOUNT; scripts/ci/run-ios-test-passes.sh attaches the image"
    )
)
struct FirestoreDiskFullSurvivalTests {
    /// Urjita's climb, with the memory-cache kill switch pulled: the phone had room at launch,
    /// so Firestore got its persistent cache, and the volume filled during the climb.
    @Test @MainActor
    func aPersistentCacheClimbOnAVolumeThatFillsKeepsRecordingAndSaysTheBoardCouldNotRefresh() async throws {
        let mount = try #require(FirestoreDiskFullLab.mountPoint)
        try FirestoreDiskFullLab.freeVolume(mount)
        try FirestoreDiskFullLab.prepareCacheDirectory(appName: "disk-full-gate", mountPoint: mount)
        let shippedFlags = RemoteFeatureFlagStore.shared.snapshot
        RemoteFeatureFlagStore.shared.apply(.resolving(remoteValues: [RemoteFeatureFlag.firestoreMemoryCache.key: false]))
        defer {
            RemoteFeatureFlagStore.shared.apply(shippedFlags)
            FirestoreDiskGuard.shared.decideCacheMode(on: VolumeFreeSpaceReader())
        }

        var activatedMode: FirestoreCacheMode?
        let db = try await FirestoreDiskFullLab.makeFirestore(appName: "disk-full-gate") { db in
            activatedMode = FirestoreDiskGuard.shared.activate(applyingTo: db, on: LabVolumeReader(mountPoint: mount))
        }
        #expect(
            activatedMode == .persistent(sizeBytes: FirestoreDiskPolicy.boundedPersistentCacheSizeBytes),
            "with room at launch the process gets the bounded persistent cache, as a phone would"
        )
        #expect(FirestoreDiskGuard.shared.allowsLocalCacheWrite())

        let service = LiveReplayLeaderboardService(
            repository: FirestoreLiveReplayLeaderboardRepository(db: db),
            fetchTimeoutSeconds: 6
        )
        let container = try Self.makeContainer()
        let viewModel = Self.makeSession(leaderboardService: service)
        viewModel.start(modelContext: container.mainContext)

        // Before the fill the reads reach the SDK: they fail (the network is off) but the
        // listens are allocated and released in LevelDB, which is what wrote the cache's log.
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)
        #expect(viewModel.phase == .recording)

        let fill = FirestoreDiskFullLab.fill(mount)
        #expect(fill.lastError.contains("No space left on device"), "the volume is genuinely full: \(fill)")
        #expect(FirestoreDiskGuard.shared.allowsLocalCacheWrite() == false)

        for tick in 1...40 {
            await viewModel.refreshReplayLeaderboardIfNeeded(force: true)
            #expect(viewModel.leaderboardFetchFailed, "tick \(tick): the board says it could not refresh")
            #expect(viewModel.phase == .recording, "tick \(tick): the session keeps recording")
        }

        // The direct form of the same guarantee, for the reader who does not know the view model.
        let context = LiveReplayLeaderboardContext.liveClimb(climbId: Self.climb.id, targetSteps: Self.climb.referenceStepCount)
        await #expect(throws: FirestoreLowDiskRefusal.self) {
            try await service.refreshIfNeeded(context: context, elapsedSeconds: 300, currentSteps: 700, force: true)
        }

        await viewModel.discard(modelContext: container.mainContext)
    }

    /// The shipped state on a phone that is already full: no LevelDB at all, so the same reads
    /// that aborted the process before now simply fail offline, forty times over.
    @Test @MainActor
    func aFullVolumeRunsFirestoreInMemoryAndTheReadsCannotAbort() async throws {
        let mount = try #require(FirestoreDiskFullLab.mountPoint)
        // The directory first, then the fill: a full volume cannot take even an empty folder.
        try FirestoreDiskFullLab.freeVolume(mount)
        try FirestoreDiskFullLab.prepareCacheDirectory(appName: "disk-full-memory", mountPoint: mount)
        let fill = FirestoreDiskFullLab.fill(mount)
        #expect(fill.lastError.contains("No space left on device"), "the volume is genuinely full: \(fill)")
        defer { FirestoreDiskGuard.shared.decideCacheMode(on: VolumeFreeSpaceReader()) }

        var activatedMode: FirestoreCacheMode?
        let db = try await FirestoreDiskFullLab.makeFirestore(appName: "disk-full-memory") { db in
            activatedMode = FirestoreDiskGuard.shared.activate(applyingTo: db, on: LabVolumeReader(mountPoint: mount))
        }
        #expect(activatedMode == .memory)
        #expect(FirestoreDiskGuard.shared.allowsLocalCacheWrite(), "a memory process has nothing to protect")

        var snapshots = 0
        for index in 0..<40 {
            snapshots += try await FirestoreDiskFullLab.listenOnce(db, marker: "memory-\(index)")
        }
        #expect(snapshots == 40)

        let service = LiveReplayLeaderboardService(
            repository: FirestoreLiveReplayLeaderboardRepository(db: db),
            fetchTimeoutSeconds: 6
        )
        let context = LiveReplayLeaderboardContext.liveClimb(climbId: Self.climb.id, targetSteps: Self.climb.referenceStepCount)
        for tick in 1...10 {
            do {
                _ = try await service.refreshIfNeeded(context: context, elapsedSeconds: tick * 5, currentSteps: tick * 7, force: true)
                Issue.record("the network is disabled, so the read cannot have an answer")
            } catch {
                #expect(
                    ServerReadFailureClass.classify(error) == .unreachable,
                    "tick \(tick): the SDK was asked and said offline, nothing worse: \(error)"
                )
            }
        }
    }

    @MainActor
    private static func makeSession(leaderboardService: any LiveReplayLeaderboardServicing) -> LiveClimbSessionViewModel {
        LiveClimbSessionViewModel(
            climb: climb,
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: leaderboardService
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static let climb = Climb(
        id: "empire-state-building",
        name: "Empire State Building",
        city: "New York",
        country: "United States",
        continent: "North America",
        latitude: 40.7484,
        longitude: -73.9857,
        totalHeightMeters: 443,
        totalHeightFeet: 1_454,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 2_437,
        realStairCount: 1_576,
        calculatedFloors: 86,
        category: "skyscraper",
        tier: .gold,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )
}
