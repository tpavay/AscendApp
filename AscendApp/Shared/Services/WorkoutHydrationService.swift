import Foundation
import SwiftData

@MainActor
enum WorkoutHydrationService {
    private static var hydratedUserIdsThisSession: Set<String> = []
    private static var hydratingUserIds: Set<String> = []

    static func hydrateIfNeeded(
        modelContext: ModelContext,
        currentUserId: String,
        remoteRepository: any WorkoutRemoteRepositoryProtocol = WorkoutRemoteRepository.shared
    ) async throws -> Int {
        guard !hydratedUserIdsThisSession.contains(currentUserId),
              !hydratingUserIds.contains(currentUserId) else {
            return 0
        }

        hydratingUserIds.insert(currentUserId)
        defer { hydratingUserIds.remove(currentUserId) }

        let records = try await remoteRepository.fetchWorkouts(userId: currentUserId)
        hydratedUserIdsThisSession.insert(currentUserId)
        guard !records.isEmpty else { return 0 }

        let localWorkouts = try fetchLocalWorkouts(modelContext: modelContext, userId: currentUserId)
        var localByID = Dictionary(uniqueKeysWithValues: localWorkouts.map { ($0.id, $0) })
        var changedCount = 0

        for record in records.sorted(by: { $0.document.startedAt < $1.document.startedAt }) {
            if let existingWorkout = localByID[record.workoutId] {
                guard shouldApplyRemoteDocument(record.document, to: existingWorkout) else { continue }
                try apply(
                    record.document,
                    workoutId: record.workoutId,
                    userId: currentUserId,
                    to: existingWorkout,
                    modelContext: modelContext
                )
                changedCount += 1
            } else {
                let workout = makeWorkout(
                    from: record.document,
                    workoutId: record.workoutId
                )
                modelContext.insert(workout)
                try apply(
                    record.document,
                    workoutId: record.workoutId,
                    userId: currentUserId,
                    to: workout,
                    modelContext: modelContext
                )
                localByID[workout.id] = workout
                changedCount += 1
            }
        }

        if changedCount > 0 {
            try modelContext.save()
        }

        return changedCount
    }

    private static func shouldApplyRemoteDocument(_ document: FirestoreWorkoutDocument, to workout: Workout) -> Bool {
        switch workout.remoteSyncStatus {
        case .pendingUpsert, .failed:
            return false
        case .synced, .rejected:
            return document.updatedAt > workout.lastModifiedAt
        }
    }

    private static func fetchLocalWorkouts(modelContext: ModelContext, userId: String) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.ownerUserId == userId
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private static func makeWorkout(
        from document: FirestoreWorkoutDocument,
        workoutId: UUID
    ) -> Workout {
        let workout = Workout(
            name: document.name,
            date: document.startedAt,
            duration: document.durationSeconds,
            steps: document.steps,
            floors: document.floors,
            stepsPerFloor: document.stepsPerFloor,
            notes: document.notes,
            avgHeartRate: document.avgHeartRateBpm,
            maxHeartRate: document.maxHeartRateBpm,
            caloriesBurned: document.caloriesBurned,
            effortRating: document.effortRating,
            averageMETs: document.averageMETs,
            source: WorkoutSource(rawValue: document.source) ?? .manual,
            deviceModel: document.deviceModel,
            sourceMetadata: document.sourceMetadata,
            healthKitUUID: document.healthKitUUID,
            hevyWorkoutId: document.hevyWorkoutId,
            photos: photos(from: document.media),
            highlightedPhotoId: document.highlightedMediaId.flatMap(UUID.init(uuidString:)),
            weightConfiguration: weightConfiguration(from: document.weightConfiguration)
        )
        workout.id = workoutId
        return workout
    }

    private static func apply(
        _ document: FirestoreWorkoutDocument,
        workoutId: UUID,
        userId: String,
        to workout: Workout,
        modelContext: ModelContext
    ) throws {
        workout.id = workoutId
        workout.name = document.name
        workout.date = document.startedAt
        workout.duration = document.durationSeconds
        workout.steps = document.steps
        workout.floors = document.floors
        workout.stepsPerFloor = document.stepsPerFloor
        workout.notes = document.notes
        workout.createdAt = document.createdAt
        workout.ownerUserId = userId
        workout.lastModifiedAt = document.updatedAt
        workout.lastRemoteSyncAt = Date()
        workout.lastRemoteHeartRateSeriesStoragePath = document.heartRateSeries?.storagePath
        workout.remoteSyncStatus = .synced
        workout.lastRemoteSyncError = nil
        workout.avgHeartRate = document.avgHeartRateBpm
        workout.maxHeartRate = document.maxHeartRateBpm
        workout.caloriesBurned = document.caloriesBurned
        workout.effortRating = document.effortRating
        workout.averageMETs = document.averageMETs
        workout.source = WorkoutSource(rawValue: document.source) ?? .manual
        workout.integrityLevel = DataIntegrityLevel(rawValue: document.integrityLevel) ?? (workout.source.isVerified ? .verified : .unverified)
        workout.deviceModel = document.deviceModel
        workout.sourceMetadata = document.sourceMetadata
        workout.healthKitUUID = document.healthKitUUID
        workout.hevyWorkoutId = document.hevyWorkoutId
        workout.photos = photos(from: document.media)
        workout.highlightedPhotoId = document.highlightedMediaId.flatMap(UUID.init(uuidString:)) ?? workout.photos.first?.id
        workout.weightConfiguration = weightConfiguration(from: document.weightConfiguration)

        try replaceParticipations(
            on: workout,
            with: document.participations ?? [],
            modelContext: modelContext
        )
        try restoreLiveClimbAttemptIfNeeded(
            for: workout,
            modelContext: modelContext
        )
    }

    private static func replaceParticipations(
        on workout: Workout,
        with remoteParticipations: [FirestoreWorkoutParticipation],
        modelContext: ModelContext
    ) throws {
        for participation in workout.participations {
            modelContext.delete(participation)
        }
        workout.participations.removeAll()

        let restored = remoteParticipations.compactMap { remote -> WorkoutParticipation? in
            guard let id = UUID(uuidString: remote.id),
                  let contextType = WorkoutParticipationContextType(rawValue: remote.contextType),
                  let role = WorkoutParticipationRole(rawValue: remote.role),
                  let verificationTier = WorkoutParticipationVerificationTier(rawValue: remote.verificationTier) else {
                return nil
            }

            return WorkoutParticipation(
                id: id,
                workout: workout,
                userId: remote.userId,
                contextType: contextType,
                contextId: remote.contextId,
                contextVersion: remote.contextVersion,
                rulesVersion: remote.rulesVersion,
                role: role,
                leaderboardEligible: remote.leaderboardEligible,
                verificationTier: verificationTier,
                metricsSnapshot: WorkoutParticipationMetricsSnapshot(
                    startedAt: remote.metricsSnapshot.startedAt,
                    durationSeconds: remote.metricsSnapshot.durationSeconds,
                    steps: remote.metricsSnapshot.steps,
                    floors: remote.metricsSnapshot.floors,
                    stepsPerMinute: remote.metricsSnapshot.stepsPerMinute
                ),
                createdAt: remote.createdAt
            )
        }

        workout.participations = restored
        for participation in restored {
            modelContext.insert(participation)
        }
    }

    private static func restoreLiveClimbAttemptIfNeeded(
        for workout: Workout,
        modelContext: ModelContext
    ) throws {
        guard workout.source == .headphoneMotion,
              let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout),
              metadata.trackingMode == .liveClimb,
              let climbId = metadata.climbId,
              let attemptId = liveClimbAttemptId(for: workout) else {
            return
        }

        let status = LiveClimbCompletionPolicy.attemptStatus(for: metadata, steps: workout.steps)
        let recordedSteps = LiveClimbCompletionPolicy.recordedSteps(
            steps: workout.steps,
            targetStepCount: LiveClimbCompletionPolicy.targetStepCount(for: metadata)
        )
        let endedAt = workout.date.addingTimeInterval(workout.duration)
        let descriptor = FetchDescriptor<ClimbAttempt>(
            predicate: #Predicate<ClimbAttempt> { attempt in
                attempt.id == attemptId
            }
        )
        let existingAttempt = try modelContext.fetch(descriptor).first
        let attempt = existingAttempt ?? ClimbAttempt(
            climbId: climbId,
            status: status,
            startedAt: workout.date,
            endedAt: endedAt,
            completedAt: status == .completed ? endedAt : nil,
            accumulatedSteps: recordedSteps,
            accumulatedDurationSeconds: Int(workout.duration.rounded()),
            sessionsCount: 1,
            appliedWorkoutIds: [workout.id.uuidString],
            bestCompletionDurationSeconds: status == .completed ? Int(workout.duration.rounded()) : nil
        )

        attempt.id = attemptId
        attempt.climbId = climbId
        attempt.status = status
        attempt.startedAt = workout.date
        attempt.endedAt = endedAt
        attempt.completedAt = status == .completed ? endedAt : nil
        attempt.accumulatedSteps = recordedSteps
        attempt.accumulatedDurationSeconds = Int(workout.duration.rounded())
        attempt.sessionsCount = 1
        attempt.appliedWorkoutIds = [workout.id.uuidString]
        attempt.bestCompletionDurationSeconds = status == .completed ? Int(workout.duration.rounded()) : nil

        if existingAttempt == nil {
            modelContext.insert(attempt)
        }
    }

    private static func liveClimbAttemptId(for workout: Workout) -> UUID? {
        workout.participations
            .first { $0.contextType == .climbAttempt }
            .flatMap { UUID(uuidString: $0.contextId) }
    }

    private static func photos(from media: [FirestoreWorkoutMediaItem]?) -> [Photo] {
        media?.compactMap { item in
            guard let id = UUID(uuidString: item.id),
                  let url = URL(string: item.url),
                  let type = MediaType(rawValue: item.type) else {
                return nil
            }

            return Photo(
                id: id,
                url: url,
                uploadedAt: item.uploadedAt,
                type: type,
                duration: item.durationSeconds
            )
        } ?? []
    }

    private static func weightConfiguration(from remote: FirestoreWorkoutWeightConfiguration?) -> WeightConfiguration? {
        guard let remote else { return nil }

        let entries = remote.entries.compactMap { entry -> WeightEntry? in
            guard let id = UUID(uuidString: entry.id),
                  let equipmentType = WeightEquipmentType(rawValue: entry.equipmentType) else {
                return nil
            }

            return WeightEntry(
                id: id,
                equipmentType: equipmentType,
                weightValue: entry.weightValue,
                isEnabled: entry.isEnabled
            )
        }

        return entries.isEmpty ? nil : WeightConfiguration(entries: entries)
    }
}
