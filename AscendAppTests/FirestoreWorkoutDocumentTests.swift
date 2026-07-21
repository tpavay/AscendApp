import Foundation
import Testing
@testable import AscendApp

struct FirestoreWorkoutDocumentTests {
    @Test
    func workoutDocumentIDCanonicalizesEveryUUIDCase() throws {
        let lowercase = "51c91094-5475-4b25-ab8f-a5d809f90a2f"
        let uppercase = lowercase.uppercased()
        let workoutID = try #require(UUID(uuidString: lowercase))

        #expect(WorkoutDocumentID.canonicalString(from: lowercase) == uppercase)
        #expect(WorkoutDocumentID.canonicalString(from: uppercase) == uppercase)
        #expect(WorkoutDocumentID.canonicalString(for: workoutID) == uppercase)
        #expect(WorkoutDocumentID.isCanonical(lowercase) == false)
        #expect(WorkoutDocumentID.isCanonical(uppercase))
    }

    @Test
    func headphoneMotionSourceIsVerifiedAndNotAProvider() {
        #expect(WorkoutSource.headphoneMotion.rawValue == "headphone_motion")
        #expect(WorkoutSource.headphoneMotion.displayName == "Headphone Tracking")
        #expect(WorkoutSource.headphoneMotion.isVerified)
        #expect(WorkoutProvider(workoutSource: .headphoneMotion) == nil)
    }

    @Test
    func workoutDocumentRoundTripsWithNestedContracts() throws {
        let createdAt = makeDate(year: 2026, month: 4, day: 11, hour: 8)
        let updatedAt = makeDate(year: 2026, month: 4, day: 11, hour: 9)
        let startedAt = makeDate(year: 2026, month: 4, day: 10, hour: 6, minute: 30)

        let document = FirestoreWorkoutDocument(
            userId: "user-123",
            name: "Morning Stair Stepper",
            startedAt: startedAt,
            durationSeconds: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            notes: "Felt strong",
            source: "apple_health",
            climbId: nil,
            integrityLevel: "verified",
            createdAt: createdAt,
            updatedAt: updatedAt,
            avgHeartRateBpm: 142,
            maxHeartRateBpm: 168,
            caloriesBurned: 310,
            effortRating: 4.5,
            averageMETs: 8.2,
            deviceModel: "Apple Watch",
            sourceMetadata: "{\"sourceDevice\":\"Apple Watch\"}",
            healthKitUUID: "550E8400-E29B-41D4-A716-446655440000",
            hevyWorkoutId: "hevy-123",
            media: [
                FirestoreWorkoutMediaItem(
                    id: "11111111-1111-1111-1111-111111111111",
                    url: "https://example.com/photo.jpg",
                    uploadedAt: updatedAt,
                    type: "photo"
                )
            ],
            highlightedMediaId: "11111111-1111-1111-1111-111111111111",
            weightConfiguration: FirestoreWorkoutWeightConfiguration(
                entries: [
                    FirestoreWorkoutWeightEntry(
                        id: "22222222-2222-2222-2222-222222222222",
                        equipmentType: "weighted_vest",
                        weightValue: 20,
                        isEnabled: true
                    )
                ]
            ),
            heartRateSeries: FirestoreWorkoutHeartRateSeriesReference(
                storagePath: "users/user-123/workout_heart_rate/550e8400-e29b-41d4-a716-446655440000.json.gz",
                sampleCount: 3,
                seriesStartAt: startedAt,
                seriesEndAt: updatedAt
            ),
            participations: [
                FirestoreWorkoutParticipation(
                    id: "33333333-3333-3333-3333-333333333333",
                    workoutId: "550e8400-e29b-41d4-a716-446655440000",
                    userId: "user-123",
                    contextType: "routine_template",
                    contextId: "pyramid_climb",
                    contextVersion: 1,
                    rulesVersion: 1,
                    role: "primary",
                    leaderboardEligible: true,
                    verificationTier: "provider_verified",
                    metricsSnapshot: FirestoreWorkoutParticipationMetricsSnapshot(
                        startedAt: startedAt,
                        durationSeconds: 1_800,
                        steps: 1_200,
                        floors: 75,
                        stepsPerMinute: 40
                    ),
                    createdAt: updatedAt
                )
            ]
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(FirestoreWorkoutDocument.self, from: encoded)

        #expect(decoded == document)
        #expect(decoded.schemaVersion == FirestoreWorkoutDocument.currentSchemaVersion)
    }

    @Test
    func heartRateSeriesReferenceDefaultsToGzippedJsonEncoding() {
        let start = makeDate(year: 2026, month: 4, day: 10, hour: 6)
        let end = makeDate(year: 2026, month: 4, day: 10, hour: 6, minute: 45)

        let reference = FirestoreWorkoutHeartRateSeriesReference(
            storagePath: "users/user-123/workout_heart_rate/550e8400-e29b-41d4-a716-446655440000.json.gz",
            sampleCount: 24,
            seriesStartAt: start,
            seriesEndAt: end
        )

        #expect(reference.encoding == FirestoreWorkoutHeartRateSeriesReference.defaultEncoding)
        #expect(reference.seriesEndAt >= reference.seriesStartAt)
    }

    @Test
    func heartRateStorageBlobRoundTripsSamples() throws {
        let start = makeDate(year: 2026, month: 4, day: 10, hour: 6)
        let samples = [
            HeartRateDataPoint(timestamp: start, heartRate: 118),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(300), heartRate: 132),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(600), heartRate: 145)
        ]

        let blob = WorkoutHeartRateStorageBlob(
            workoutId: "550e8400-e29b-41d4-a716-446655440000",
            samples: samples
        )

        let encoded = try JSONEncoder().encode(blob)
        let decoded = try JSONDecoder().decode(WorkoutHeartRateStorageBlob.self, from: encoded)

        #expect(decoded == blob)
        #expect(decoded.samples.count == 3)
        #expect(decoded.schemaVersion == WorkoutHeartRateStorageBlob.currentSchemaVersion)
    }

    @Test
    func heartRateStorageBlobCompressionProducesReadableGzip() throws {
        let start = makeDate(year: 2026, month: 4, day: 10, hour: 6)
        let blob = WorkoutHeartRateStorageBlob(
            workoutId: "550e8400-e29b-41d4-a716-446655440000",
            samples: [
                HeartRateDataPoint(timestamp: start, heartRate: 118),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(300), heartRate: 132)
            ]
        )
        let encoded = try JSONEncoder().encode(blob)

        let compressed = try GzipCodec.compress(encoded)
        let decompressed = try GzipCodec.decompress(compressed)
        let decoded = try JSONDecoder().decode(WorkoutHeartRateStorageBlob.self, from: decompressed)

        #expect(compressed.starts(with: Data([0x1f, 0x8b, 0x08])))
        #expect(decompressed == encoded)
        #expect(decoded == blob)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
