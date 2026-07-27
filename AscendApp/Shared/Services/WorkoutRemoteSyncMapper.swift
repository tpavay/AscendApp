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

        let heartRateBlob = try heartRateBlob(for: workout)
        let heartRateSeriesReference = heartRateBlob.map { blob in
            let seriesBounds = seriesBounds(for: blob.samples)
            return FirestoreWorkoutHeartRateSeriesReference(
                storagePath: WorkoutHeartRateStoragePath.path(
                    userId: userId,
                    workoutId: workout.id
                ),
                sampleCount: blob.samples.count,
                seriesStartAt: seriesBounds.start,
                seriesEndAt: seriesBounds.end
            )
        }

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

    static func heartRateBlob(for workout: Workout) throws -> WorkoutHeartRateStorageBlob? {
        let samples = workout.heartRateTimeSeries
        guard !samples.isEmpty else { return nil }

        guard samples.allSatisfy({ $0.heartRate > 0 }) else {
            throw WorkoutSyncError.invalidHeartRateSeries
        }

        return WorkoutHeartRateStorageBlob(
            workoutId: workout.id.uuidString,
            samples: samples
        )
    }

    static func seriesBounds(for samples: [HeartRateDataPoint]) -> (start: Date, end: Date) {
        let start = samples.map(\.timestamp).min() ?? .distantPast
        let end = samples.map(\.timestamp).max() ?? start
        return (start, end)
    }
}
