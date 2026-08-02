import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// The failure in issue #304, shaped the way a climber meets it: build a
/// routine, put it in a folder, get a new phone, sign back in.
///
/// Before this change there was no upload path, no hydration path and no
/// Firestore schema for routines, so the wipe below was permanent. Every test
/// here fails on that code - the first one because nothing is ever uploaded,
/// the rest because there is nothing to restore from.
@MainActor
@Suite(.serialized)
struct RoutineCloudBackupRoundTripTests {
    private static let userId = "user-304"

    @Test("A reinstall gets the climber's routines and folders back", .bug(id: 304))
    func reinstallRestoresRoutinesAndFolders() async throws {
        let backend = InMemoryUserRoutineBackend()
        let coordinator = makeSyncCoordinator(backend)

        // ── The phone the climber built the routine on ──
        let firstDevice = try makeModelContext()
        let service = makeService(modelContext: firstDevice, coordinator: coordinator)

        let folder = try service.createFolder(name: "Race prep", colorHex: "#86D30A", order: 1)
        let routine = try service.createRoutine(
            name: "Tuesday Pyramid",
            description: "Build to 14, then unwind.",
            intervals: makeIntervals(),
            folderId: folder.id,
            difficulty: 7,
            defaultWeightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 20)
            ])
        )
        routine.completionCount = 4
        routine.lastCompletedAt = Date(timeIntervalSince1970: 1_770_000_000)
        try service.updateRoutine(routine)

        await coordinator.processPendingRoutines(
            modelContext: firstDevice,
            currentUserId: Self.userId
        )

        #expect(await backend.routineCount() == 1)
        #expect(await backend.folderCount() == 1)

        // ── The new phone: an empty store, same account ──
        let secondDevice = try makeModelContext()
        #expect(try secondDevice.fetch(FetchDescriptor<Routine>()).isEmpty)

        RoutineHydrationService.resetSessionTrackingForTesting()
        let restoredCount = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: secondDevice,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        #expect(restoredCount == 2)

        let restoredRoutine = try #require(
            try secondDevice.fetch(FetchDescriptor<Routine>()).first
        )
        #expect(restoredRoutine.id == routine.id)
        #expect(restoredRoutine.name == "Tuesday Pyramid")
        #expect(restoredRoutine.routineDescription == "Build to 14, then unwind.")
        #expect(restoredRoutine.source == .userCreated)
        #expect(restoredRoutine.folderId == folder.id)
        #expect(restoredRoutine.difficulty == 7)
        #expect(restoredRoutine.completionCount == 4)
        #expect(restoredRoutine.lastCompletedAt == routine.lastCompletedAt)
        #expect(restoredRoutine.intervals == routine.intervals)
        #expect(
            restoredRoutine.defaultWeightConfiguration?.entries.first?.equipmentType == .weightedVest
        )
        #expect(restoredRoutine.defaultWeightConfiguration?.entries.first?.weightValue == 20)

        let restoredFolder = try #require(
            try secondDevice.fetch(FetchDescriptor<RoutineFolder>()).first
        )
        #expect(restoredFolder.id == folder.id)
        #expect(restoredFolder.name == "Race prep")
        #expect(restoredFolder.colorHex == "#86D30A")
        #expect(restoredFolder.order == 1)
    }

    @Test("An archived routine comes back archived rather than resurrected", .bug(id: 304))
    func archivedRoutineRestoresArchived() async throws {
        let backend = InMemoryUserRoutineBackend()
        let coordinator = makeSyncCoordinator(backend)
        let firstDevice = try makeModelContext()
        let service = makeService(modelContext: firstDevice, coordinator: coordinator)

        let routine = try service.createRoutine(name: "Retired", intervals: makeIntervals())
        try service.archiveRoutine(routine)

        await coordinator.processPendingRoutines(
            modelContext: firstDevice,
            currentUserId: Self.userId
        )

        let secondDevice = try makeModelContext()
        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: secondDevice,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        let restored = try #require(try secondDevice.fetch(FetchDescriptor<Routine>()).first)
        #expect(restored.isArchived)
    }

    @Test("A deleted routine stays deleted on the next device", .bug(id: 304))
    func deletedRoutineDoesNotComeBack() async throws {
        let backend = InMemoryUserRoutineBackend()
        let coordinator = makeSyncCoordinator(backend)
        let firstDevice = try makeModelContext()
        let service = makeService(modelContext: firstDevice, coordinator: coordinator)

        let routine = try service.createRoutine(name: "Mistake", intervals: makeIntervals())
        await coordinator.processPendingRoutines(
            modelContext: firstDevice,
            currentUserId: Self.userId
        )
        #expect(await backend.routineCount() == 1)

        try service.deleteRoutine(routine)
        await coordinator.processPendingRoutines(
            modelContext: firstDevice,
            currentUserId: Self.userId
        )
        #expect(await backend.routineCount() == 0)

        let secondDevice = try makeModelContext()
        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: secondDevice,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        #expect(try secondDevice.fetch(FetchDescriptor<Routine>()).isEmpty)
    }

    @Test("Catalog templates are never uploaded as the climber's own content", .bug(id: 304))
    func catalogTemplatesAreNotBackedUp() async throws {
        let backend = InMemoryUserRoutineBackend()
        let coordinator = makeSyncCoordinator(backend)
        let modelContext = try makeModelContext()
        let service = makeService(modelContext: modelContext, coordinator: coordinator)

        let template = Routine(
            name: "Pyramid Climb",
            source: .remoteTemplate,
            intervals: makeIntervals(),
            templateId: "pyramid_climb"
        )
        modelContext.insert(template)
        let userCopy = try service.copyBuiltInRoutine(template)
        try modelContext.save()

        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let uploadedIds = await backend.uploadedRoutineIds()
        #expect(uploadedIds == [userCopy.id])
    }

    // MARK: - Helpers

    private func makeService(
        modelContext: ModelContext,
        coordinator: RoutineSyncCoordinator
    ) -> RoutineService {
        RoutineService(
            modelContext: modelContext,
            templateRepository: StubRoutineTemplateRepository(),
            syncCoordinator: coordinator,
            currentUserId: { Self.userId }
        )
    }

    private func makeSyncCoordinator(_ backend: InMemoryUserRoutineBackend) -> RoutineSyncCoordinator {
        RoutineSyncCoordinator(remoteRepository: backend, operationTimeoutSeconds: 5)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Routine.self,
            RoutineFolder.self,
            PendingRoutineDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeIntervals() -> [RoutineInterval] {
        [
            RoutineInterval(duration: 120, intensityValue: 8, order: 0),
            RoutineInterval(
                duration: 60,
                intensityType: .stepsPerMinute,
                intensityValue: 90,
                modifiers: IntervalModifiers(
                    sidewaysDirection: .left,
                    skipStep: true,
                    holdingBars: true,
                    weightOverride: IntervalWeightOverride(enabledEquipmentTypes: [.weightedVest])
                ),
                order: 1
            ),
            RoutineInterval(
                duration: 180,
                intensityValue: 14,
                modifiers: IntervalModifiers(weightOverride: .noWeights),
                order: 2
            )
        ]
    }
}

/// A stand-in for `users/{uid}/routines` and `users/{uid}/routine_folders` that
/// behaves like Firestore: documents keyed by id, last write wins, deletes
/// remove them.
actor InMemoryUserRoutineBackend: UserRoutineRemoteRepositoryProtocol {
    private var routines: [UUID: FirestoreUserRoutineDocument] = [:]
    private var folders: [UUID: FirestoreRoutineFolderDocument] = [:]
    private var upsertOrder: [UUID] = []

    var upsertError: (any Error & Sendable)?
    var deleteError: (any Error & Sendable)?

    init(
        upsertError: (any Error & Sendable)? = nil,
        deleteError: (any Error & Sendable)? = nil
    ) {
        self.upsertError = upsertError
        self.deleteError = deleteError
    }

    func fetchRoutines(userId: String) async throws -> [RemoteUserRoutineRecord] {
        routines
            .map { RemoteUserRoutineRecord(routineId: $0.key, document: $0.value) }
            .filter { $0.document.userId == userId }
    }

    func fetchFolders(userId: String) async throws -> [RemoteRoutineFolderRecord] {
        folders
            .map { RemoteRoutineFolderRecord(folderId: $0.key, document: $0.value) }
            .filter { $0.document.userId == userId }
    }

    func upsertRoutine(
        userId: String,
        routineId: UUID,
        document: FirestoreUserRoutineDocument
    ) async throws {
        if let upsertError { throw upsertError }
        routines[routineId] = document
        upsertOrder.append(routineId)
    }

    func upsertFolder(
        userId: String,
        folderId: UUID,
        document: FirestoreRoutineFolderDocument
    ) async throws {
        if let upsertError { throw upsertError }
        folders[folderId] = document
        upsertOrder.append(folderId)
    }

    func deleteRoutine(userId: String, routineId: UUID) async throws {
        if let deleteError { throw deleteError }
        routines[routineId] = nil
    }

    func deleteFolder(userId: String, folderId: UUID) async throws {
        if let deleteError { throw deleteError }
        folders[folderId] = nil
    }

    // MARK: - Inspection

    func routineCount() -> Int { routines.count }
    func folderCount() -> Int { folders.count }
    func uploadedRoutineIds() -> [UUID] { Array(routines.keys) }
    func routineDocument(_ routineId: UUID) -> FirestoreUserRoutineDocument? { routines[routineId] }
    func folderDocument(_ folderId: UUID) -> FirestoreRoutineFolderDocument? { folders[folderId] }
    func upsertSequence() -> [UUID] { upsertOrder }

    func seedRoutine(_ routineId: UUID, document: FirestoreUserRoutineDocument) {
        routines[routineId] = document
    }

    func seedFolder(_ folderId: UUID, document: FirestoreRoutineFolderDocument) {
        folders[folderId] = document
    }

    func setUpsertError(_ error: (any Error & Sendable)?) {
        upsertError = error
    }

    func setDeleteError(_ error: (any Error & Sendable)?) {
        deleteError = error
    }
}

/// The catalog repository is irrelevant to the backup path, so tests stub it out
/// rather than reaching for the live Firestore one.
struct StubRoutineTemplateRepository: RoutineTemplateRepository {
    func fetchPublishedTemplates() async throws -> [RemoteRoutineTemplate] { [] }
}
