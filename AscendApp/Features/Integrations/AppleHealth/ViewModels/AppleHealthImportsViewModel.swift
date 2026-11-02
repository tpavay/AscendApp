import Foundation
import Observation

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

    @ObservationIgnored private let service: AppleHealthImportService
    @ObservationIgnored private let undoWindow: Duration
    @ObservationIgnored private var toastTask: Task<Void, Never>?

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
    func onAppear() async {
        service.markImportsViewed()
        await service.syncNow()
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
