import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Renders the heart-rate surfaces a signed-in user actually sees on a clean device after the
/// durable sidecar round trip, so the restore behaviour can be reviewed visually rather than only
/// through assertions. Writes PNGs to `ASCEND_EVIDENCE_DIR` when set, and renders nothing otherwise.
@MainActor
struct WorkoutHeartRateRestoreEvidenceTests {
    @Test
    func capturesHeartRateChartRestoredFromSidecarAndItsFailureStates() async throws {
        let userId = "evidence-restore-user"
        let workoutId = UUID(uuidString: "1D8E5D2C-4A31-4C67-9C2B-6F0A1B2C3D4E")!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = Self.makeClimbSeries(start: start)

        let sourceWorkout = Workout(
            name: "Evening climb",
            date: start,
            duration: 1_800,
            steps: 2_400,
            floors: 150,
            stepsPerFloor: 16,
            notes: "",
            avgHeartRate: 138,
            maxHeartRate: 167,
            heartRateTimeSeries: samples,
            source: .appleHealth
        )
        sourceWorkout.id = workoutId
        sourceWorkout.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: start)

        // Upload leg: the same snapshot the sync coordinator sends.
        let snapshot = try WorkoutRemoteSyncMapper.snapshot(from: sourceWorkout)
        let blob = try #require(snapshot.heartRateBlob)
        let sidecarRepository = EvidenceSidecarRepository(blob: blob)
        let reference = try await sidecarRepository.uploadHeartRateSeries(
            userId: userId,
            workoutId: workoutId,
            blob: blob
        )
        let document = snapshot.document.replacingHeartRateSeries(reference)

        // Download leg: clean signed-in device with no local samples.
        let cleanDeviceContext = try Self.makeContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: cleanDeviceContext,
            currentUserId: userId,
            remoteRepository: EvidenceRemoteRepository(
                records: [RemoteWorkoutRecord(workoutId: workoutId, document: document)]
            ),
            heartRateStorageRepository: sidecarRepository
        )

        let restored = try #require(
            try cleanDeviceContext.fetch(FetchDescriptor<Workout>()).first
        )
        #expect(restored.heartRateTimeSeries == samples)
        #expect(restored.heartRateRestoreStatus == .ready)

        try Self.render(
            name: "01-restored-chart-clean-device",
            caption: "Clean signed-in device after sidecar restore - \(restored.heartRateTimeSeries.count) samples",
            content: HeartRateChartView(
                heartRateData: restored.heartRateTimeSeries,
                workoutStartTime: restored.date,
                workoutDuration: restored.duration,
                averageHeartRateBpm: restored.avgHeartRate,
                maxHeartRateBpm: restored.maxHeartRate
            )
        )

        // The states the same screen shows while the sidecar has not landed.
        let transient = try #require(
            try await Self.hydratedWorkout(
                userId: "\(userId)-transient",
                document: document,
                repository: FailingSidecarRepository(error: .transient)
            )
        )
        #expect(transient.heartRateRestoreStatus == .retryPending)
        #expect(transient.heartRateRestoreErrorCode == "transient")

        // The in-flight state: what hydration writes while a download is running, and what tapping
        // retry on the card puts the workout back into.
        transient.heartRateRestoreStatus = .pending
        try Self.render(
            name: "02-restore-pending",
            caption: "Restore in flight (status: \(transient.heartRateRestoreStatus.rawValue))",
            content: WorkoutHeartRateRestoreCard(
                status: transient.heartRateRestoreStatus,
                effectiveColorScheme: .dark,
                onRetry: {}
            )
        )
        transient.heartRateRestoreStatus = .retryPending

        try Self.render(
            name: "03-restore-retry-pending-offline",
            caption: "Transient failure (status: \(transient.heartRateRestoreStatus.rawValue), code: \(transient.heartRateRestoreErrorCode ?? "-"))",
            content: WorkoutHeartRateRestoreCard(
                status: transient.heartRateRestoreStatus,
                effectiveColorScheme: .dark,
                onRetry: {}
            )
        )

        let integrity = try #require(
            try await Self.hydratedWorkout(
                userId: "\(userId)-integrity",
                document: document,
                repository: FailingSidecarRepository(error: .integrityMismatch)
            )
        )
        #expect(integrity.heartRateRestoreStatus == .unavailable)
        #expect(integrity.heartRateRestoreErrorCode == "integrity_failed")
        try Self.render(
            name: "04-restore-unavailable-integrity",
            caption: "Integrity failure (status: \(integrity.heartRateRestoreStatus.rawValue), code: \(integrity.heartRateRestoreErrorCode ?? "-"))",
            content: WorkoutHeartRateRestoreCard(
                status: integrity.heartRateRestoreStatus,
                effectiveColorScheme: .dark,
                onRetry: {}
            )
        )

        let forbidden = try #require(
            try await Self.hydratedWorkout(
                userId: "\(userId)-forbidden",
                document: document,
                repository: FailingSidecarRepository(error: .forbidden)
            )
        )
        #expect(forbidden.heartRateRestoreStatus == .unavailable)
        #expect(forbidden.heartRateRestoreErrorCode == "forbidden")

        let missing = try #require(
            try await Self.hydratedWorkout(
                userId: "\(userId)-missing",
                document: document,
                repository: FailingSidecarRepository(error: .missing)
            )
        )
        #expect(missing.heartRateRestoreErrorCode == "missing")

        let malformed = try #require(
            try await Self.hydratedWorkout(
                userId: "\(userId)-malformed",
                document: document,
                repository: FailingSidecarRepository(error: .malformed)
            )
        )
        #expect(malformed.heartRateRestoreErrorCode == "malformed")

        print(
            """
            ASCEND_EVIDENCE_SUMMARY \
            restored_samples=\(restored.heartRateTimeSeries.count) \
            uploaded_samples=\(samples.count) \
            lossless=\(restored.heartRateTimeSeries == samples) \
            sidecar_path=\(reference.storagePath) \
            sha256=\(reference.sha256 ?? "-") \
            bytes=\(reference.compressedByteCount ?? -1) \
            statuses=[transient:\(transient.heartRateRestoreStatus.rawValue)/\(transient.heartRateRestoreErrorCode ?? "-"), \
            integrity:\(integrity.heartRateRestoreStatus.rawValue)/\(integrity.heartRateRestoreErrorCode ?? "-"), \
            forbidden:\(forbidden.heartRateRestoreStatus.rawValue)/\(forbidden.heartRateRestoreErrorCode ?? "-"), \
            missing:\(missing.heartRateRestoreStatus.rawValue)/\(missing.heartRateRestoreErrorCode ?? "-"), \
            malformed:\(malformed.heartRateRestoreStatus.rawValue)/\(malformed.heartRateRestoreErrorCode ?? "-")]
            """
        )
    }

    private static func hydratedWorkout(
        userId: String,
        document: FirestoreWorkoutDocument,
        repository: any WorkoutHeartRateStorageRepositoryProtocol
    ) async throws -> Workout? {
        let workoutId = UUID()
        let scopedReference = FirestoreWorkoutHeartRateSeriesReference(
            storagePath: WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId),
            sampleCount: document.heartRateSeries?.sampleCount ?? 1,
            seriesStartAt: document.heartRateSeries?.seriesStartAt ?? document.startedAt,
            seriesEndAt: document.heartRateSeries?.seriesEndAt ?? document.startedAt
        )
        let scopedDocument = FirestoreWorkoutDocument(
            userId: userId,
            name: document.name,
            startedAt: document.startedAt,
            durationSeconds: document.durationSeconds,
            steps: document.steps,
            floors: document.floors,
            stepsPerFloor: document.stepsPerFloor,
            notes: document.notes,
            source: document.source,
            climbId: document.climbId,
            integrityLevel: document.integrityLevel,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            avgHeartRateBpm: document.avgHeartRateBpm,
            maxHeartRateBpm: document.maxHeartRateBpm,
            heartRateSeries: scopedReference
        )

        let context = try makeContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: EvidenceRemoteRepository(
                records: [RemoteWorkoutRecord(workoutId: workoutId, document: scopedDocument)]
            ),
            heartRateStorageRepository: repository
        )
        return try context.fetch(FetchDescriptor<Workout>()).first
    }

    private static func makeClimbSeries(start: Date) -> [HeartRateDataPoint] {
        let shape: [Int] = [
            96, 104, 112, 121, 128, 133, 137, 140, 142, 145,
            149, 152, 148, 144, 147, 153, 158, 162, 165, 167,
            163, 157, 150, 146, 149, 154, 159, 161, 156, 148,
            141, 134, 128, 122, 117, 112, 108, 104, 101, 98
        ]
        return shape.enumerated().map { index, bpm in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(Double(index) * 45),
                heartRate: bpm
            )
        }
    }

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            PendingWorkoutDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// The captioned surface, photographed at 3x only when `ASCEND_EVIDENCE_DIR` is set.
    private static func render(
        name: String,
        caption: String,
        content: some View
    ) throws {
        let framed = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
            content
        }
        .padding(20)
        .frame(width: 402)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        try RenderedScreen.photograph(framed, named: name)
    }
}

private actor EvidenceSidecarRepository: WorkoutHeartRateStorageRepositoryProtocol {
    private let blob: WorkoutHeartRateStorageBlob
    private var storedObjects: [String: Data] = [:]

    init(blob: WorkoutHeartRateStorageBlob) {
        self.blob = blob
    }

    /// Mirrors the production upload: gzip the canonical blob and publish the integrity metadata the
    /// download side later verifies.
    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        let path = WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)
        let compressed = try GzipCodec.compress(JSONEncoder().encode(blob))
        storedObjects[path] = compressed

        return FirestoreWorkoutHeartRateSeriesReference(
            storagePath: path,
            sampleCount: blob.samples.count,
            seriesStartAt: blob.samples.map(\.timestamp).min() ?? .distantPast,
            seriesEndAt: blob.samples.map(\.timestamp).max() ?? .distantPast,
            objectSchemaVersion: blob.schemaVersion,
            compressedByteCount: compressed.count,
            sha256: SHA256.hash(data: compressed).map { String(format: "%02x", $0) }.joined()
        )
    }

    /// Mirrors the production download: owner-scoped fetch, then the real validator.
    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        let path = try WorkoutHeartRateSidecarValidator.validatedStoragePath(
            userId: userId,
            workoutId: workoutId,
            reference: reference
        )
        guard let compressed = storedObjects[path] else {
            throw WorkoutHeartRateSidecarError.missing
        }
        return try WorkoutHeartRateSidecarValidator.validate(
            compressedData: compressed,
            userId: userId,
            workoutId: workoutId,
            reference: reference
        )
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {
        storedObjects[WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)] = nil
    }
}

private struct FailingSidecarRepository: WorkoutHeartRateStorageRepositoryProtocol {
    let error: WorkoutHeartRateSidecarError

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        throw error
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        throw error
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {}
}

private struct EvidenceRemoteRepository: WorkoutRemoteRepositoryProtocol {
    let records: [RemoteWorkoutRecord]

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        records.filter { $0.document.userId == userId }
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {}

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}
}
