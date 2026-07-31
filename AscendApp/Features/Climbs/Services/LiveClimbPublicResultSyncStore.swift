import FirebaseAuth
import Foundation
import Observation
import SwiftData

enum LiveClimbPublicResultPhase: Equatable {
    case pending
    case savedOnDevice
    case syncingRanking
    case syncFailedRetry
    case published
}

struct LiveClimbPublicResultSyncStatus: Equatable {
    let phase: LiveClimbPublicResultPhase
    let rankSnapshot: LiveReplayCompletionRankSnapshot?
    let publishStatus: LiveReplayPublishStatus?

    var isPublished: Bool {
        phase == .published
    }

    var canRetry: Bool {
        phase == .syncFailedRetry
    }

    static let pending = LiveClimbPublicResultSyncStatus(
        phase: .pending,
        rankSnapshot: nil,
        publishStatus: nil
    )
}

@MainActor
@Observable
final class LiveClimbPublicResultSyncStore {
    static let shared = LiveClimbPublicResultSyncStore()

    private let leaderboardService: LiveReplayLeaderboardServicing
    private let connectivityService: NetworkConnectivityService
    private let completedRankService: CompletedClimbRankService
    private var retryTasksByWorkoutId: [UUID: Task<Void, Never>] = [:]
    private(set) var statusesByWorkoutId: [UUID: LiveClimbPublicResultSyncStatus] = [:]

    init(
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared,
        connectivityService: NetworkConnectivityService = .shared,
        completedRankService: CompletedClimbRankService = .shared
    ) {
        self.leaderboardService = leaderboardService
        self.connectivityService = connectivityService
        self.completedRankService = completedRankService
    }

    func status(for workoutId: UUID) -> LiveClimbPublicResultSyncStatus? {
        statusesByWorkoutId[workoutId]
    }

    func refresh(
        workout: Workout,
        climb: Climb
    ) async {
        let status = await resolvedStatus(workout: workout, climb: climb)
        statusesByWorkoutId[workout.id] = status
    }

    /// Polls only while the result is still settling. A workout whose rank is already frozen is
    /// finished competitive history - there is nothing left to wait for, so a reopened summary
    /// costs zero requests.
    func refreshUntilRankPublished(
        workout: Workout,
        climb: Climb,
        maxAttempts: Int = 4,
        delaySeconds: UInt64 = 1_500_000_000
    ) async {
        let attempts = max(maxAttempts, 1)

        if let frozen = completedRankService.frozenRank(
            context: leaderboardContext(for: climb),
            workoutId: workout.id.uuidString
        ) {
            statusesByWorkoutId[workout.id] = LiveClimbPublicResultSyncStatus(
                phase: .published,
                rankSnapshot: frozen,
                publishStatus: statusesByWorkoutId[workout.id]?.publishStatus
            )
            return
        }

        for attempt in 0..<attempts {
            await refresh(workout: workout, climb: climb)
            guard statusesByWorkoutId[workout.id]?.phase != .published else {
                return
            }
            guard attempt < attempts - 1,
                  connectivityService.isConnected else {
                return
            }

            try? await Task.sleep(nanoseconds: delaySeconds)
        }
    }

    func retrySync(
        workout: Workout,
        climb: Climb,
        modelContext: ModelContext
    ) async {
        guard retryTasksByWorkoutId[workout.id] == nil else { return }
        guard let userId = workout.ownerUserId ?? Auth.auth().currentUser?.uid else {
            statusesByWorkoutId[workout.id] = LiveClimbPublicResultSyncStatus(
                phase: .syncFailedRetry,
                rankSnapshot: nil,
                publishStatus: nil
            )
            return
        }

        let workoutId = workout.id
        statusesByWorkoutId[workoutId] = LiveClimbPublicResultSyncStatus(
            phase: connectivityService.isConnected ? .syncingRanking : .savedOnDevice,
            rankSnapshot: statusesByWorkoutId[workoutId]?.rankSnapshot,
            publishStatus: statusesByWorkoutId[workoutId]?.publishStatus
        )

        let task = Task { @MainActor in
            defer {
                retryTasksByWorkoutId[workoutId] = nil
            }

            guard connectivityService.isConnected else {
                statusesByWorkoutId[workoutId] = LiveClimbPublicResultSyncStatus(
                    phase: .savedOnDevice,
                    rankSnapshot: nil,
                    publishStatus: statusesByWorkoutId[workoutId]?.publishStatus
                )
                return
            }

            workout.markPendingRemoteUpsert(ownerUserId: userId)
            do {
                try modelContext.save()
            } catch {
                statusesByWorkoutId[workoutId] = LiveClimbPublicResultSyncStatus(
                    phase: .syncFailedRetry,
                    rankSnapshot: nil,
                    publishStatus: statusesByWorkoutId[workoutId]?.publishStatus
                )
                return
            }

            await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                modelContext: modelContext,
                currentUserId: userId
            )
            await refreshUntilRankPublished(workout: workout, climb: climb)
        }

        retryTasksByWorkoutId[workoutId] = task
        await task.value
    }

    private func leaderboardContext(for climb: Climb) -> LiveReplayLeaderboardContext {
        .liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
    }

    private func resolvedStatus(
        workout: Workout,
        climb: Climb
    ) async -> LiveClimbPublicResultSyncStatus {
        let context = leaderboardContext(for: climb)
        let workoutId = workout.id.uuidString

        async let fetchedSnapshot = completedRankService.resolveFrozenRank(
            context: context,
            workoutId: workoutId
        )
        async let fetchedPublishStatus = leaderboardService.fetchPublishStatus(
            workoutId: workoutId
        )

        let rankSnapshot = await fetchedSnapshot
        let publishStatus = try? await fetchedPublishStatus

        if let rankSnapshot {
            return LiveClimbPublicResultSyncStatus(
                phase: .published,
                rankSnapshot: rankSnapshot,
                publishStatus: publishStatus
            )
        }

        if retryTasksByWorkoutId[workout.id] != nil {
            return LiveClimbPublicResultSyncStatus(
                phase: connectivityService.isConnected ? .syncingRanking : .savedOnDevice,
                rankSnapshot: nil,
                publishStatus: publishStatus
            )
        }

        if connectivityService.isConnected == false,
           workout.remoteSyncStatus == .pendingUpsert || workout.remoteSyncStatus == .failed {
            return LiveClimbPublicResultSyncStatus(
                phase: .savedOnDevice,
                rankSnapshot: nil,
                publishStatus: publishStatus
            )
        }

        switch workout.remoteSyncStatus {
        case .pendingUpsert:
            return LiveClimbPublicResultSyncStatus(
                phase: .pending,
                rankSnapshot: nil,
                publishStatus: publishStatus
            )
        case .failed, .rejected:
            return LiveClimbPublicResultSyncStatus(
                phase: .syncFailedRetry,
                rankSnapshot: nil,
                publishStatus: publishStatus
            )
        case .synced:
            switch publishStatus?.state {
            case .published:
                return LiveClimbPublicResultSyncStatus(
                    phase: .published,
                    rankSnapshot: nil,
                    publishStatus: publishStatus
                )
            case .publishing:
                return LiveClimbPublicResultSyncStatus(
                    phase: .syncingRanking,
                    rankSnapshot: nil,
                    publishStatus: publishStatus
                )
            case .failedRetryable:
                return LiveClimbPublicResultSyncStatus(
                    phase: .syncFailedRetry,
                    rankSnapshot: nil,
                    publishStatus: publishStatus
                )
            case nil:
                return LiveClimbPublicResultSyncStatus(
                    phase: .pending,
                    rankSnapshot: nil,
                    publishStatus: nil
                )
            }
        }
    }
}
