import Foundation

enum WorkoutRemoteSyncMapper {
    static func snapshot(from workout: Workout) throws -> WorkoutRemoteSyncSnapshot {
        guard let userId = workout.ownerUserId, !userId.isEmpty else {
            throw WorkoutSyncError.missingOwner
        }

        guard supportedSourceRawValues.contains(workout.source.rawValue) else {
            throw WorkoutSyncError.unsupportedSource(workout.source.rawValue)
        }

        guard WorkoutPlausibilityPolicy.hasPlausibleTotals(workout) else {
            throw WorkoutSyncError.implausibleWorkoutTotals
        }

        let media = workout.photos.isEmpty
            ? nil
            : workout.photos.map { photo in
                FirestoreWorkoutMediaItem(
                    id: photo.id.uuidString,
                    url: photo.url.absoluteString,
                    uploadedAt: photo.uploadedAt,
                    type: photo.type.rawValue,
                    durationSeconds: photo.duration
                )
            }

        let highlightedMediaId = workout.highlightedPhotoId.flatMap { highlightedId in
            workout.photos.contains(where: { $0.id == highlightedId }) ? highlightedId.uuidString : nil
        }

        let weightConfiguration = workout.weightConfiguration.flatMap { config in
            config.entries.isEmpty ? nil : FirestoreWorkoutWeightConfiguration(
                entries: config.entries.map { entry in
                    FirestoreWorkoutWeightEntry(
                        id: entry.id.uuidString,
                        equipmentType: entry.equipmentType.rawValue,
                        weightValue: entry.weightValue,
                        isEnabled: entry.isEnabled
                    )
                }
            )
        }

        let heartRateBlob = heartRateBlob(for: workout)
        let heartRateSeriesReference = heartRateSeriesReference(
            for: workout,
            userId: userId,
            blob: heartRateBlob
        )

        let participations = workout.participations.isEmpty
            ? nil
            : workout.participations
                .sorted { $0.createdAt < $1.createdAt }
                .map { participation in
                    firestoreParticipation(participation, workout: workout, userId: userId)
                }

        let document = FirestoreWorkoutDocument(
            userId: userId,
            name: workout.name,
            startedAt: workout.date,
            durationSeconds: workout.duration,
            steps: workout.steps,
            floors: workout.floors,
            stepsPerFloor: workout.stepsPerFloor,
            notes: workout.notes,
            source: workout.source.rawValue,
            climbId: climbId(from: workout),
            integrityLevel: workout.integrityLevel.rawValue,
            createdAt: workout.createdAt,
            updatedAt: workout.lastModifiedAt,
            avgHeartRateBpm: workout.avgHeartRate,
            maxHeartRateBpm: workout.maxHeartRate,
            caloriesBurned: workout.caloriesBurned,
            effortRating: workout.effortRating,
            averageMETs: workout.averageMETs,
            deviceModel: workout.deviceModel,
            sourceMetadata: workout.sourceMetadata,
            healthKitUUID: workout.healthKitUUID,
            hevyWorkoutId: workout.hevyWorkoutId,
            media: media,
            highlightedMediaId: highlightedMediaId,
            weightConfiguration: weightConfiguration,
            heartRateSeries: heartRateSeriesReference,
            participations: participations
        )

        return WorkoutRemoteSyncSnapshot(
            workoutId: workout.id,
            userId: userId,
            createdAt: workout.createdAt,
            lastModifiedAt: workout.lastModifiedAt,
            document: document,
            heartRateBlob: heartRateBlob,
            previousHeartRateSeriesStoragePath: workout.lastRemoteHeartRateSeriesStoragePath
        )
    }
}

private extension WorkoutRemoteSyncMapper {
    static let supportedSourceRawValues: Set<String> = [
        WorkoutSource.manual.rawValue,
        WorkoutSource.appleHealth.rawValue,
        WorkoutSource.garmin.rawValue,
        WorkoutSource.fitbit.rawValue,
        WorkoutSource.hevy.rawValue,
        WorkoutSource.headphoneMotion.rawValue
    ]

    static func climbId(from workout: Workout) -> String? {
        guard workout.source == .headphoneMotion,
              let sourceMetadata = workout.sourceMetadata,
              let data = sourceMetadata.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(HeadphoneMotionWorkoutMetadata.self, from: data),
              let climbId = metadata.climbId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !climbId.isEmpty else {
            return nil
        }
        return climbId
    }

    static func firestoreParticipation(
        _ participation: WorkoutParticipation,
        workout: Workout,
        userId: String
    ) -> FirestoreWorkoutParticipation {
        let snapshot = participation.metricsSnapshot ?? WorkoutParticipationMetricsSnapshot(workout: workout)

        return FirestoreWorkoutParticipation(
            id: participation.id.uuidString,
            workoutId: workout.id.uuidString,
            userId: participation.userId ?? userId,
            contextType: participation.contextType.rawValue,
            contextId: participation.contextId,
            contextVersion: participation.contextVersion,
            rulesVersion: participation.rulesVersion,
            role: participation.role.rawValue,
            leaderboardEligible: participation.leaderboardEligible,
            verificationTier: participation.verificationTier.rawValue,
            metricsSnapshot: FirestoreWorkoutParticipationMetricsSnapshot(
                startedAt: snapshot.startedAt,
                durationSeconds: snapshot.durationSeconds,
                steps: snapshot.steps,
                floors: snapshot.floors,
                stepsPerMinute: snapshot.stepsPerMinute
            ),
            createdAt: participation.createdAt
        )
    }

    /// Out-of-range samples are dropped individually, never by rejecting the workout. One glitched
    /// strap or import reading must not cost the rest of the series, the workout, or - because
    /// snapshot failures abort the whole pass - every other workout waiting to back up.
    /// `WorkoutHeartRatePlausibilityRepair` normally clears them from the stored series first; this
    /// filter is what keeps the uploaded sidecar satisfying the download validator regardless.
    static func heartRateBlob(for workout: Workout) -> WorkoutHeartRateStorageBlob? {
        let plausibleSamples = workout.heartRateTimeSeries
            .filter(WorkoutHeartRateSidecarValidator.isPlausibleSample)
        guard !plausibleSamples.isEmpty else { return nil }

        return WorkoutHeartRateStorageBlob(
            workoutId: workout.id.uuidString,
            samples: plausibleSamples
        )
    }

    /// A workout with no local samples only clears its remote sidecar when the local absence is
    /// authoritative. While a restore is still pending, unavailable, or awaiting retry, the last
    /// known reference is carried forward so the durable series stays reachable - unless the
    /// sidecar it points at was confirmed absent, in which case the dangling reference is dropped.
    static func heartRateSeriesReference(
        for workout: Workout,
        userId: String,
        blob: WorkoutHeartRateStorageBlob?
    ) -> FirestoreWorkoutHeartRateSeriesReference? {
        guard let blob else {
            guard workout.heartRateRestoreStatus.treatsLocalAbsenceAsAuthoritative == false,
                  workout.lastHeartRateSidecarFailure?.preservesRemoteReference ?? true else {
                return nil
            }
            return workout.lastRemoteHeartRateSeriesReference
        }

        let bounds = seriesBounds(for: blob.samples)
        return FirestoreWorkoutHeartRateSeriesReference(
            storagePath: WorkoutHeartRateStoragePath.path(
                userId: userId,
                workoutId: workout.id
            ),
            sampleCount: blob.samples.count,
            seriesStartAt: bounds.start,
            seriesEndAt: bounds.end
        )
    }

    static func seriesBounds(for samples: [HeartRateDataPoint]) -> (start: Date, end: Date) {
        let start = samples.map(\.timestamp).min() ?? .distantPast
        let end = samples.map(\.timestamp).max() ?? start
        return (start, end)
    }
}
