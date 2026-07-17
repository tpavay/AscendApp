import Foundation
import SwiftData

/// How a routine workout came to exist. Routine completions come only from the live routine
/// flow, so manual entries and external imports can never earn competitive credit.
enum RoutineAttributionOrigin: Equatable, Sendable {
    case liveSession(stopReason: HeadphoneMotionSessionStopReason)
    case manualEntry
}

struct RoutineWorkoutAttribution: Equatable {
    let routineId: UUID
    let routineSource: RoutineSource
    let templateId: String?
    let origin: RoutineAttributionOrigin

    init(
        routineId: UUID,
        routineSource: RoutineSource,
        templateId: String?,
        origin: RoutineAttributionOrigin
    ) {
        self.routineId = routineId
        self.routineSource = routineSource
        self.templateId = templateId
        self.origin = origin
    }

    var contextType: WorkoutParticipationContextType {
        routineSource.isTemplate && templateId?.isEmpty == false
            ? .routineTemplate
            : .routine
    }

    var contextId: String {
        if contextType == .routineTemplate, let templateId {
            return templateId
        }

        return routineId.uuidString
    }

    /// `targetReached` is the only stop reason that earns competitive credit: it is the gate the
    /// server-side replay indexer publishes on, and skipping burns the routine clock without steps.
    var isLeaderboardEligible: Bool {
        guard contextType == .routineTemplate else { return false }

        switch origin {
        case .liveSession(let stopReason):
            return stopReason == .targetReached
        case .manualEntry:
            return false
        }
    }
}

@MainActor
enum WorkoutParticipationService {
    static let currentRoutineRulesVersion = 1
    static let currentClimbAttemptRulesVersion = 1

    static func addRoutineParticipationIfNeeded(
        for workout: Workout,
        attribution: RoutineWorkoutAttribution?,
        userId: String?,
        modelContext: ModelContext
    ) throws {
        guard let attribution else { return }

        try addParticipationIfNeeded(
            for: workout,
            userId: userId,
            contextType: attribution.contextType,
            contextId: attribution.contextId,
            rulesVersion: currentRoutineRulesVersion,
            role: .primary,
            leaderboardEligible: attribution.isLeaderboardEligible,
            verificationTier: .sourceDefault(for: workout.source),
            modelContext: modelContext
        )
    }

    static func addClimbAttemptParticipationIfNeeded(
        for workout: Workout,
        attempt: ClimbAttempt,
        userId: String?,
        leaderboardEligible: Bool,
        modelContext: ModelContext
    ) throws {
        try addParticipationIfNeeded(
            for: workout,
            userId: userId,
            contextType: .climbAttempt,
            contextId: attempt.id.uuidString,
            rulesVersion: currentClimbAttemptRulesVersion,
            role: .primary,
            leaderboardEligible: leaderboardEligible,
            verificationTier: .sourceDefault(for: workout.source),
            modelContext: modelContext
        )
    }

    static func setLeaderboardEligibility(
        _ leaderboardEligible: Bool,
        forClimbAttemptId attemptId: UUID,
        workoutId: UUID? = nil,
        modelContext: ModelContext
    ) throws {
        let contextId = attemptId.uuidString
        let contextType = WorkoutParticipationContextType.climbAttempt.rawValue
        let descriptor = FetchDescriptor<WorkoutParticipation>(
            predicate: #Predicate {
                $0.contextTypeRawValue == contextType &&
                $0.contextId == contextId
            }
        )

        for participation in try modelContext.fetch(descriptor) {
            if let workoutId, participation.workoutId != workoutId {
                continue
            }

            participation.leaderboardEligible = leaderboardEligible
            markWorkoutPendingRemoteSyncIfPossible(participation.workout, fallbackUserId: participation.userId)
        }
    }

    private static func addParticipationIfNeeded(
        for workout: Workout,
        userId: String?,
        contextType: WorkoutParticipationContextType,
        contextId: String,
        rulesVersion: Int,
        role: WorkoutParticipationRole,
        leaderboardEligible: Bool,
        verificationTier: WorkoutParticipationVerificationTier,
        modelContext: ModelContext
    ) throws {
        guard workout.participations.contains(where: {
            $0.contextType == contextType && $0.contextId == contextId
        }) == false else {
            return
        }

        let participation = WorkoutParticipation(
            workout: workout,
            userId: userId,
            contextType: contextType,
            contextId: contextId,
            contextVersion: 1,
            rulesVersion: rulesVersion,
            role: role,
            leaderboardEligible: leaderboardEligible,
            verificationTier: verificationTier
        )

        workout.participations.append(participation)
        modelContext.insert(participation)
        markWorkoutPendingRemoteSyncIfPossible(workout, fallbackUserId: userId)
    }

    private static func markWorkoutPendingRemoteSyncIfPossible(
        _ workout: Workout?,
        fallbackUserId: String?
    ) {
        guard let workout,
              let userId = workout.ownerUserId ?? fallbackUserId,
              !userId.isEmpty else {
            return
        }

        workout.markPendingRemoteUpsert(ownerUserId: userId)
    }
}
