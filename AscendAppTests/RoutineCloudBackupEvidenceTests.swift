import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Product-level evidence for issue #304, shaped the way a climber meets it:
/// build routines on one phone, get a new phone, sign back in.
///
/// Everything below runs through the real path - `RoutineService` for the
/// mutations, `RoutineSyncCoordinator` for the upload, the real Firestore
/// document encoder for what lands on the server, `RoutineHydrationService` for
/// the restore, and `RoutineListViewModel` plus the same components
/// `RoutinesView` renders for what the climber sees. The two rendered panels
/// are the before/after of the bug: an empty My Routines on the new phone, and
/// the same phone after the restore.
///
/// The backup documents are dumped alongside the image so a reviewer can read
/// the exact per-user Firestore payload the rules test exercises. Both are
/// written only when `ASCEND_EVIDENCE_DIR` is set (`RenderedScreen`).
@MainActor
struct RoutineCloudBackupEvidenceTests {
    /// Unique to this suite so it never collides with another suite's hydration
    /// session tracking, and so it never has to clear that process-wide state
    /// out from under a suite running in parallel.
    private static let userId = "climber-304-evidence"

    @Test("Routine cloud backup reinstall evidence", .bug(id: 304))
    func rendersReinstallRestore() async throws {
        let backend = InMemoryUserRoutineBackend()
        // Own feature-flag store, so a parallel suite flipping the shared
        // singleton cannot decide what this evidence shows.
        let flags = RemoteFeatureFlagStore()
        let coordinator = RoutineSyncCoordinator(
            remoteRepository: backend,
            featureFlags: flags,
            operationTimeoutSeconds: 5
        )

        // ── The phone the climber built the routines on ──
        let oldPhone = try makeModelContext()
        let service = RoutineService(
            modelContext: oldPhone,
            templateRepository: StubRoutineTemplateRepository(),
            syncCoordinator: coordinator,
            currentUserId: { Self.userId }
        )

        let folder = try service.createFolder(name: "Race prep", colorHex: "#86D30A", order: 0)
        let pyramid = try service.createRoutine(
            name: "Tuesday Pyramid",
            description: "Build to 14, then unwind.",
            intervals: pyramidIntervals(),
            folderId: folder.id,
            difficulty: 7,
            defaultWeightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 20)
            ])
        )
        let grind = try service.createRoutine(
            name: "Sunday Grind",
            description: "Thirty minutes, one gear, no excuses.",
            intervals: grindIntervals(),
            difficulty: 5
        )

        // Finishing a routine is the mutation that never goes through the
        // editor, so it is the one most likely to be missing from a backup.
        try service.recordCompletion(
            for: pyramid,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        await coordinator.processPendingRoutines(
            modelContext: oldPhone,
            currentUserId: Self.userId
        )

        #expect(await backend.routineCount() == 2)
        #expect(await backend.folderCount() == 1)

        // ── The new phone: an empty store, same account ──
        let newPhone = try makeModelContext()
        #expect(try newPhone.fetch(FetchDescriptor<Routine>()).isEmpty)

        let beforeViewModel = RoutineListViewModel()
        beforeViewModel.configure(modelContext: newPhone)
        beforeViewModel.loadRoutines()
        #expect(beforeViewModel.hasMyRoutines == false)

        let restoredCount = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: newPhone,
            currentUserId: Self.userId,
            remoteRepository: backend,
            featureFlags: flags
        )
        #expect(restoredCount == 3)

        let afterViewModel = RoutineListViewModel()
        afterViewModel.configure(modelContext: newPhone)
        afterViewModel.loadRoutines()

        // What the climber gets back, read out of the new phone's store.
        let restoredRoutines = afterViewModel.filteredMyRoutines
        #expect(restoredRoutines.count == 2)
        let restoredPyramid = try #require(restoredRoutines.first { $0.id == pyramid.id })
        #expect(restoredPyramid.name == "Tuesday Pyramid")
        #expect(restoredPyramid.completionCount == 1)
        #expect(restoredPyramid.intervals == pyramid.intervals)
        #expect(restoredPyramid.folderId == folder.id)
        #expect(restoredRoutines.contains { $0.id == grind.id })

        let restoredFolder = try #require(
            try newPhone.fetch(FetchDescriptor<RoutineFolder>()).first
        )
        #expect(restoredFolder.id == folder.id)
        #expect(restoredFolder.name == "Race prep")

        // ── Evidence ──
        try await writeBackupDocuments(
            backend: backend,
            routineIds: [pyramid.id, grind.id],
            folderId: folder.id
        )

        try RenderedScreen.photograph(
            RoutineBackupProof(
                beforeViewModel: beforeViewModel,
                afterViewModel: afterViewModel,
                restoredFolderName: restoredFolder.name,
                restoredFolderColorHex: restoredFolder.colorHex
            ),
            named: "routine-cloud-backup-reinstall"
        )
    }

    // MARK: - Evidence

    /// Proves the upload put every document in the backend, and writes them out keyed
    /// by the Firestore path they live at - the dump only under `ASCEND_EVIDENCE_DIR`.
    private func writeBackupDocuments(
        backend: InMemoryUserRoutineBackend,
        routineIds: [UUID],
        folderId: UUID
    ) async throws {
        var routines: [BackedUpRoutine] = []
        for routineId in routineIds {
            let document = try #require(await backend.routineDocument(routineId))
            routines.append(
                BackedUpRoutine(
                    path: "users/\(Self.userId)/routines/\(routineId.uuidString)",
                    document: document
                )
            )
        }

        let folderDocument = try #require(await backend.folderDocument(folderId))
        let dump = BackupDump(
            routines: routines,
            folders: [
                BackedUpFolder(
                    path: "users/\(Self.userId)/routine_folders/\(folderId.uuidString)",
                    document: folderDocument
                )
            ]
        )

        guard let directory = RenderedScreen.evidenceDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appending(path: "routine-cloud-backup-documents.json")
        try encoder.encode(dump).write(to: url)
        print("Routine cloud backup documents: \(url.path())")
    }

    // MARK: - Fixtures

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Routine.self,
            RoutineFolder.self,
            PendingRoutineDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func pyramidIntervals() -> [RoutineInterval] {
        [
            RoutineInterval(duration: 180, intensityValue: 6, order: 0),
            RoutineInterval(duration: 120, intensityValue: 9, order: 1),
            RoutineInterval(duration: 120, intensityValue: 12, order: 2),
            RoutineInterval(
                duration: 90,
                intensityValue: 14,
                modifiers: IntervalModifiers(
                    holdingBars: true,
                    weightOverride: IntervalWeightOverride(enabledEquipmentTypes: [.weightedVest])
                ),
                order: 3
            ),
            RoutineInterval(duration: 120, intensityValue: 10, order: 4),
            RoutineInterval(duration: 180, intensityValue: 6, order: 5)
        ]
    }

    private func grindIntervals() -> [RoutineInterval] {
        [
            RoutineInterval(duration: 300, intensityValue: 7, order: 0),
            RoutineInterval(
                duration: 600,
                intensityType: .stepsPerMinute,
                intensityValue: 85,
                order: 1
            ),
            RoutineInterval(duration: 300, intensityValue: 8, order: 2)
        ]
    }
}

// MARK: - Evidence payloads

private struct BackupDump: Encodable {
    let routines: [BackedUpRoutine]
    let folders: [BackedUpFolder]
}

private struct BackedUpRoutine: Encodable {
    let path: String
    let document: FirestoreUserRoutineDocument
}

private struct BackedUpFolder: Encodable {
    let path: String
    let document: FirestoreRoutineFolderDocument
}

// MARK: - Proof surface

/// The My Routines surface as `RoutinesView` renders it - same section label,
/// same rail, same `RoutineThumbnailCard` configuration, same empty state -
/// shown for the new phone before and after the cloud restore.
private struct RoutineBackupProof: View {
    let beforeViewModel: RoutineListViewModel
    let afterViewModel: RoutineListViewModel
    let restoredFolderName: String
    let restoredFolderColorHex: String?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            panel(
                title: "NEW PHONE - BEFORE",
                caption: "Signed in, nothing restored. This is what issue #304 left behind.",
                viewModel: beforeViewModel,
                footer: nil
            )

            panel(
                title: "NEW PHONE - AFTER SIGN-IN",
                caption: "Restored from users/{uid}/routines and routine_folders.",
                viewModel: afterViewModel,
                footer: "Folder restored: \(restoredFolderName) \(restoredFolderColorHex ?? "")"
            )
        }
        .padding(28)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func panel(
        title: String,
        caption: String,
        viewModel: RoutineListViewModel,
        footer: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)

            Text(caption)
                .font(.montserratRegular(size: 12))
                .foregroundStyle(Color.customGray)
                .fixedSize(horizontal: false, vertical: true)

            myRoutinesSection(viewModel)

            if let footer {
                Text(footer)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(Color(hex: "86D30A"))
            }

            Spacer(minLength: 0)
        }
        .frame(width: 468, height: 300, alignment: .topLeading)
    }

    private func myRoutinesSection(_ viewModel: RoutineListViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MY ROUTINES")
                .font(.montserratSemiBold(size: 12))
                .tracking(0.8)
                .foregroundStyle(Color.customGray)

            if viewModel.hasMyRoutines {
                // `RoutinesView` puts these cards in a `RoutineHorizontalRail`.
                // The rail's `ScrollView` renders blank in an offscreen render,
                // which defers scroll-content layout, so the rail's own `HStack`
                // spacing is used directly here. The cards are the real ones,
                // configured exactly as the screen configures them.
                HStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.filteredMyRoutines) { routine in
                        RoutineThumbnailCard(
                            routine: routine,
                            width: 208,
                            height: 118,
                            chartHeight: 40,
                            widthMode: .proportionalToDuration,
                            showsLevelRange: true
                        )
                    }
                }
            } else {
                RoutineGhostCard()
            }
        }
    }
}
