import Foundation
import Observation
import SwiftData

/// The Imports screen's actions and its Undo toast.
///
/// Importing never opens a sheet or a dialog: a tap imports, the row moves, and a toast offers to
/// take it back for five seconds. A second import inside that window joins the same toast, so Undo
/// always takes back everything the climber just did, not only the last tap.
@MainActor
@Observable
final class AppleHealthImportsViewModel {
    struct Toast: Equatable {
        let batch: AppleHealthImportService.ImportBatch

        var message: String {
            batch.count == 1 ? "1 climb imported" : "\(batch.count) climbs imported"
        }
    }

    private(set) var toast: Toast?
    /// What the screen draws, rebuilt when the store saves rather than on every draw: the ledger
    /// grows for the life of the account, and the toast and the animations redraw the screen often.
    private(set) var sections = ImportsSections()

    @ObservationIgnored private let service: AppleHealthImportService
    @ObservationIgnored private let undoWindow: Duration
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var modelContext: ModelContext?

    init(
        service: AppleHealthImportService = .shared,
        undoWindow: Duration = AppleHealthImportPolicy.undoWindow
    ) {
        self.service = service
        self.undoWindow = undoWindow
    }

    var isAutoImportEnabled: Bool { service.isAutoImportEnabled }

    var autoImportSubtitle: String {
        isAutoImportEnabled
            ? "New stair stepper workouts are imported for you."
            : "You choose which workouts to import."
    }

    /// Opening Imports empties the badge, then catches up with anything Health holds that the
    /// background pass has not seen yet.
    ///
    /// Viewed again once the catch-up is done, so a workout it found while the climber was looking
    /// does not raise the badge they just cleared.
    func onAppear(modelContext: ModelContext) async {
        self.modelContext = modelContext
        reload()
        service.markImportsViewed()
        await service.syncNow()
        service.markImportsViewed()
        reload()
    }

    /// Rebuilds the sections from the store: the screen's rows, and only the steps and time of the
    /// climbs those rows became.
    func reload() {
        guard let modelContext else { return }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        guard let records = try? ledger.importsScreenRecords() else { return }
        let climbIDs = records.compactMap(\.importedWorkoutID)
        let climbs = (try? ledger.climbMeasurements(forIDs: climbIDs)) ?? [:]
        sections = ImportsSections.make(records: records, climbs: climbs, now: Date())
    }

    /// The climb an imported row opens.
    func climb(withID id: UUID) -> Workout? {
        guard let modelContext else { return nil }
        return try? HealthWorkoutLedger(modelContext: modelContext).climb(withID: id)
    }

    func setAutoImportEnabled(_ isEnabled: Bool) async {
        await service.setAutoImportEnabled(isEnabled)
    }

    func importOne(_ id: String) async {
        await importRecords([id])
    }

    func importAll(_ ids: [String]) async {
        await importRecords(ids)
    }

    func skip(_ id: String) {
        service.skip(recordUUID: id)
    }

    func undo() async {
        guard let batch = toast?.batch else { return }
        dismissToast()
        await service.undo(batch)
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    private func importRecords(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let batch = await service.importRecords(withUUIDs: ids)
        guard !batch.isEmpty else { return }

        let combined = toast.map {
            AppleHealthImportService.ImportBatch(
                recordUUIDs: $0.batch.recordUUIDs + batch.recordUUIDs,
                workoutIDs: $0.batch.workoutIDs + batch.workoutIDs
            )
        } ?? batch
        toast = Toast(batch: combined)

        toastTask?.cancel()
        let window = undoWindow
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
