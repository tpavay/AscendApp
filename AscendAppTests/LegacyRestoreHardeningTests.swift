//
//  LegacyRestoreHardeningTests.swift
//  AscendAppTests
//

import FirebaseFirestore
import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// The pre-launch data-loss repair: a reinstalling tester's earned landmark completions must
/// restore correctly, and one bad backup document must never zero the whole restore.
///
/// These exercise the legacy backup shape directly - `source=headphone_motion`, metadata with no
/// trackingMode and no target key, `stopReason=target_reached`, no participation - which the older
/// `WorkoutHydrationServiceLiveClimbRestoreTests` never produce because they build through the
/// current mapper and keep modern fields.
@MainActor
struct LegacyRestoreHardeningTests {
    private static let stagingClimbIds = [
        "marina-bay-sands",
        "empire-state-building",
        "burj-khalifa",
        "sagrada-familia",
        "cn-tower"
    ]

    // MARK: Five restore as five (the bar)

    @Test
    func fiveLegacyLandmarkCompletionsRestoreAsFive() async throws {
        let userId = "legacy-five-restore-user"
        let records = Self.stagingLegacyRecords(userId: userId)

        let context = try Self.makeModelContext()
        WorkoutHydrationService.resetSessionTrackingForTesting()
        let changedCount = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: records)
        )

        #expect(changedCount == 5)

        let completedAttempts = try Self.completedAttempts(in: context)
        #expect(completedAttempts.count == 5)
        #expect(Set(completedAttempts.map(\.climbId)) == Set(Self.stagingClimbIds))

        // The Home surface the user actually reads.
        #expect(HomeDashboardViewModel.fetchCompletedClimbCount(modelContext: context) == 5)
    }

    // MARK: Idempotency - actually run it twice

    @Test
    func rehydratingOnAFreshDeviceKeepsFiveWithStableIds() async throws {
        let userId = "legacy-fresh-device-user"
        let records = Self.stagingLegacyRecords(userId: userId)

        let firstDevice = try Self.makeModelContext()
        WorkoutHydrationService.resetSessionTrackingForTesting()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: firstDevice,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: records)
        )
        let firstIds = try Self.completedAttempts(in: firstDevice).map(\.id).sorted { $0.uuidString < $1.uuidString }

        // A reinstall is a cold process hydrating a fresh store from the same remote docs.
        let freshDevice = try Self.makeModelContext()
        WorkoutHydrationService.resetSessionTrackingForTesting()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: freshDevice,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: records)
        )
        let secondIds = try Self.completedAttempts(in: freshDevice).map(\.id).sorted { $0.uuidString < $1.uuidString }

        #expect(firstIds.count == 5)
        // The deterministic id survives a fresh device.
        #expect(secondIds == firstIds)
    }

    @Test
    func rerunningHydrationOnTheSameStoreAddsNoDuplicates() async throws {
        let userId = "legacy-rerun-user"
        let workoutIds = (0..<5).map { _ in UUID() }
        let baseDate = Date(timeIntervalSince1970: 1_775_217_600)
        let context = try Self.makeModelContext()

        let firstPass = Self.stagingLegacyRecords(
            userId: userId,
            workoutIds: workoutIds,
            updatedAt: baseDate
        )
        WorkoutHydrationService.resetSessionTrackingForTesting()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: firstPass)
        )

        // Re-run on the same non-wiped store with the same workout ids but a newer updatedAt (a
        // synced edit), so reconstruction actually executes again instead of short-circuiting on
        // the sync-status guard. The deterministic attempt id must update the same attempt in place.
        let secondPass = Self.stagingLegacyRecords(
            userId: userId,
            workoutIds: workoutIds,
            updatedAt: baseDate.addingTimeInterval(3_600)
        )
        WorkoutHydrationService.resetSessionTrackingForTesting()
        let secondChanged = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: secondPass)
        )

        // Reconstruction genuinely ran the second time...
        #expect(secondChanged == 5)
        // ...and produced zero duplicate attempts.
        let allAttempts = try context.fetch(FetchDescriptor<ClimbAttempt>())
        #expect(allAttempts.count == 5)
        #expect(HomeDashboardViewModel.fetchCompletedClimbCount(modelContext: context) == 5)
    }

    // MARK: R0 - one bad doc must not zero the restore

    @Test
    func oneUndecodableBackupDoesNotZeroTheRestore() {
        let recorder = AppDiagnosticsRecorder(
            userDefaults: UserDefaults(suiteName: "legacy-restore-r0-\(UUID().uuidString)")!
        )
        let goodOne = UUID().uuidString
        let goodTwo = UUID().uuidString
        let bad = UUID().uuidString

        let records = WorkoutRemoteRepository.shared.decodeRecords(
            from: [
                (goodOne, Self.validWorkoutData(steps: 1_200)),
                (bad, Self.undecodableWorkoutData()),
                (goodTwo, Self.validWorkoutData(steps: 900))
            ],
            diagnostics: recorder
        )

        #expect(records.count == 2)
        #expect(Set(records.map { $0.workoutId.uuidString }) == Set([goodOne, goodTwo]))

        let decodeFailure = recorder.recentEvents().first { $0.name == "workout_backup_decode_failed" }
        #expect(decodeFailure != nil)
        #expect(decodeFailure?.details["workout_id"] == bad)
    }

    @Test
    func caseVariantBackupsDecodeAsOneWorkoutAndRecordAnError() throws {
        let suiteName = "case-variant-workout-id-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let recorder = AppDiagnosticsRecorder(userDefaults: userDefaults)
        let lowercase = "51c91094-5475-4b25-ab8f-a5d809f90a2f"
        let uppercase = lowercase.uppercased()
        let data = Self.validWorkoutData(steps: 2_096)

        let records = WorkoutRemoteRepository.shared.decodeRecords(
            from: [(lowercase, data), (uppercase, data)],
            diagnostics: recorder
        )

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.workoutId.uuidString == uppercase)

        let duplicate = recorder.recentEvents().first {
            $0.name == "workout_backup_case_variant_duplicate"
        }
        #expect(duplicate?.level == .error)
        #expect(duplicate?.details["canonical_workout_id"] == uppercase)
        #expect(duplicate?.details["document_ids"] == [uppercase, lowercase].sorted().joined(separator: ","))
    }

    @Test
    func caseVariantBackupDedupKeepsTheNewestPayload() throws {
        let suiteName = "case-variant-workout-id-dedup-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let recorder = AppDiagnosticsRecorder(userDefaults: userDefaults)
        let lowercase = "51c91094-5475-4b25-ab8f-a5d809f90a2f"
        let uppercase = lowercase.uppercased()
        var olderCanonical = Self.validWorkoutData(steps: 1_000)
        olderCanonical["updatedAt"] = Timestamp(date: Date(timeIntervalSince1970: 100))
        var newerAlias = Self.validWorkoutData(steps: 2_000)
        newerAlias["updatedAt"] = Timestamp(date: Date(timeIntervalSince1970: 200))

        let records = WorkoutRemoteRepository.shared.decodeRecords(
            from: [(uppercase, olderCanonical), (lowercase, newerAlias)],
            diagnostics: recorder
        )

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.document.steps == 2_000)
        #expect(record.document.updatedAt == Date(timeIntervalSince1970: 200))
    }

    // MARK: Predicate parity - Swift matches the shared vector

    @Test
    func predicateMatchesSharedParityVector() throws {
        let vector = try Self.sharedParityVector()
        #expect(vector.cases.count >= 10)

        for testCase in vector.cases {
            let actual = LegacyClimbCompletionPredicate.isRecoverableLegacyCompletion(
                source: testCase.source,
                climbId: testCase.climbId,
                stopReason: testCase.stopReason,
                steps: testCase.steps,
                targetStepCount: testCase.targetStepCount
            )
            #expect(actual == testCase.expected, "case \(testCase.name)")
        }
    }

    // MARK: - Fixtures

    private static func stagingLegacyRecords(userId: String) -> [RemoteWorkoutRecord] {
        stagingLegacyRecords(
            userId: userId,
            workoutIds: (0..<stagingClimbIds.count).map { _ in UUID() },
            updatedAt: Date(timeIntervalSince1970: 1_775_217_600)
        )
    }

    private static func stagingLegacyRecords(
        userId: String,
        workoutIds: [UUID],
        updatedAt: Date
    ) -> [RemoteWorkoutRecord] {
        let baseDate = Date(timeIntervalSince1970: 1_775_217_600)
        return zip(stagingClimbIds, workoutIds).enumerated().map { index, pair in
            let (climbId, workoutId) = pair
            return RemoteWorkoutRecord(
                workoutId: workoutId,
                document: legacyDocument(
                    userId: userId,
                    climbId: climbId,
                    steps: 1_000 + index * 100,
                    startedAt: baseDate.addingTimeInterval(Double(index) * 3_600),
                    updatedAt: updatedAt
                )
            )
        }
    }

    /// The captain's exact staging shape: headphone-motion, a distinct landmark climbId, metadata
    /// with no trackingMode and no target key, `stopReason=target_reached`, no participation, and
    /// `steps == target` (target unrecorded, so completion falls to the stop reason).
    private static func legacyDocument(
        userId: String,
        climbId: String,
        steps: Int,
        startedAt: Date,
        updatedAt: Date
    ) -> FirestoreWorkoutDocument {
        FirestoreWorkoutDocument(
            userId: userId,
            name: "\(climbId) Live Climb",
            startedAt: startedAt,
            durationSeconds: 900,
            steps: steps,
            floors: Workout.stepsToFloors(steps),
            stepsPerFloor: Workout.defaultStepsPerFloor,
            notes: "",
            source: WorkoutSource.headphoneMotion.rawValue,
            integrityLevel: DataIntegrityLevel.verified.rawValue,
            createdAt: startedAt,
            updatedAt: updatedAt,
            sourceMetadata: legacyMetadataJSON(climbId: climbId),
            participations: nil
        )
    }

    /// A legacy metadata blob carrying only the base headphone-motion fields plus a climbId. It
    /// deliberately omits `trackingMode` and every target key so it decodes the way a
    /// pre-participation backup does.
    private static func legacyMetadataJSON(climbId: String) -> String {
        """
        {"algorithmVersion":1,"climbId":"\(climbId)","sampleCount":500,\
        "sampleRateAssumptionHz":50,"source":"headphone_motion",\
        "stopReason":"target_reached"}
        """
    }

    private static func validWorkoutData(steps: Int) -> [String: Any] {
        [
            "userId": "decode-user",
            "name": "Workout",
            "startedAt": Date(),
            "durationSeconds": 900.0,
            "steps": steps,
            "floors": 10,
            "stepsPerFloor": 16,
            "notes": "",
            "source": "manual",
            "integrityLevel": "verified",
            "createdAt": Date(),
            "updatedAt": Date()
        ]
    }

    /// Omits the required `steps` field, so decoding throws and the row must be skipped.
    private static func undecodableWorkoutData() -> [String: Any] {
        var data = validWorkoutData(steps: 0)
        data.removeValue(forKey: "steps")
        return data
    }

    private static func completedAttempts(in context: ModelContext) throws -> [ClimbAttempt] {
        let completed = ClimbAttemptStatus.completed.rawValue
        return try context.fetch(
            FetchDescriptor<ClimbAttempt>(
                predicate: #Predicate<ClimbAttempt> { $0.statusRawValue == completed }
            )
        )
    }

    private static func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClimbAttempt.self,
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - Shared parity vector

    struct ParityVector: Decodable {
        let cases: [ParityCase]
    }

    struct ParityCase: Decodable {
        let name: String
        let source: String
        let climbId: String?
        let stopReason: String
        let steps: Int
        let targetStepCount: Int?
        let expected: Bool
    }

    private static func sharedParityVector() throws -> ParityVector {
        // Navigate from this test file to the repo-root shared vector so Swift and the TypeScript
        // functions test assert against the exact same cases.
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent() // AscendAppTests/
            .deletingLastPathComponent() // repo root
        let vectorURL = repoRoot.appending(
            path: "SharedTestVectors/legacy-recoverable-completion-vector.json"
        )
        let data = try Data(contentsOf: vectorURL)
        return try JSONDecoder().decode(ParityVector.self, from: data)
    }
}

private struct StubWorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol {
    let records: [RemoteWorkoutRecord]

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        records
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {}

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}
}
