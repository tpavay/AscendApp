import Foundation
import Observation
import SwiftData
@preconcurrency import FirebaseAuth

/// Brings stair workouts from Apple Health into Ascend as climbs.
///
/// ## One ledger, keyed by the workout
///
/// Every Health stair workout Ascend meets gets one `HealthWorkoutRecord`, keyed by its HealthKit
/// UUID, whose state is `notImported`, `imported`, `skipped` or `overlapsLiveClimb`. Everything
/// else follows from that row: nothing imports twice because the UUID is looked up first, a
/// skipped or removed workout never returns because `skipped` is permanent in both modes, and a
/// workout deleted in Health keeps its climb because nothing here ever reads Health's deletions.
///
/// ## Two modes, one pass
///
/// A pass reads Health from a persisted anchor, files whatever is new, and - when auto-import is
/// on - imports everything waiting. With it off the same workouts simply wait in Not imported and
/// the badge is the signal; no notification is sent. The first pass after connecting has no
/// anchor, so what it finds is history, not news: it imports in auto mode but announces nothing.
///
/// ## Why the observer exists, and what it must never do
///
/// `HealthWorkoutReading.startObserving` is what wakes the app in the background when a watch
/// saves a workout. Its completion handler is always called, and always within a bound, because
/// HealthKit stops delivering until it is.
///
/// ## The overlap hook
///
/// A workout whose window overlaps an Ascend live climb by a minute is not a second climb. It is
/// filed as `overlapsLiveClimb` and left there: the merge that lets that workout enrich the live
/// climb is a separate piece of work and reads those rows.
/// The three Apple Health states the Climb sheet's right-hand button tells apart.
enum AppleHealthEntry: Equatable {
    /// Not connected, or connected before import and never asked for workouts: Connect Health.
    case connect
    /// Connected. `badge` is the red count: zero with auto-import on, where nothing ever waits.
    case viewImports(badge: Int)
}

@MainActor
@Observable
final class AppleHealthImportService: AuthenticatedSessionWorker {
    static let shared = AppleHealthImportService()

    /// What one Import tap or Import all created, so the Undo toast can take it back.
    struct ImportBatch: Equatable, Sendable {
        let recordUUIDs: [String]
        let workoutIDs: [UUID]

        var count: Int { workoutIDs.count }
        var isEmpty: Bool { workoutIDs.isEmpty }
    }

    /// The climb the quick edit sheet is open on.
    struct QuickEditRequest: Identifiable, Equatable {
        let workoutID: UUID
        var id: UUID { workoutID }
    }

    /// What the green strip on Home says.
    struct HomeNotice: Equatable {
        let workoutID: UUID
        let startDate: Date
        let steps: Int?
        let duration: TimeInterval
    }

    // MARK: Observable state

    private(set) var isAutoImportEnabled = true
    /// The red count on the + button and the Climb sheet's Health button. Zero with auto-import on.
    private(set) var badgeCount = 0
    private(set) var homeNotice: HomeNotice?
    var quickEditRequest: QuickEditRequest?

    // MARK: Collaborators

    @ObservationIgnored private let reader: any HealthWorkoutReading
    @ObservationIgnored private let authorization: any HealthKitAuthorizationControlling
    @ObservationIgnored private let settings: AppleHealthImportSettings
    @ObservationIgnored private let notifier: any HealthImportNotifying
    @ObservationIgnored private let remover: any HealthImportClimbRemoving
    @ObservationIgnored private let featureFlags: RemoteFeatureFlagStore
    @ObservationIgnored private let sessionWorkGate: AuthenticatedBootstrapCoordinator
    @ObservationIgnored private let currentUserID: @MainActor () -> String?
    @ObservationIgnored private let joinDate: @MainActor () -> Date?
    @ObservationIgnored private let applyCreated: @MainActor (ModelContext, [Workout]) throws -> Void
    @ObservationIgnored private let isUpdateRequired: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let observerCompletionBound: Duration

    // MARK: Private state

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var isObserving = false
    /// The climber whose climbs the authenticated bootstrap has restored from the cloud in this
    /// session, behind the account-ownership gate. Only then may a pass with no anchor run.
    @ObservationIgnored private var cloudRestoreConfirmedUserID: String?

    init(
        reader: any HealthWorkoutReading = HealthKitWorkoutReader.shared,
        authorization: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        settings: AppleHealthImportSettings = AppleHealthImportSettings(),
        notifier: any HealthImportNotifying = LocalHealthImportNotifier(),
        remover: any HealthImportClimbRemoving = LiveHealthImportClimbRemover(),
        featureFlags: RemoteFeatureFlagStore = .shared,
        sessionWorkGate: AuthenticatedBootstrapCoordinator = .shared,
        currentUserID: @escaping @MainActor () -> String? = { Auth.auth().currentUser?.uid },
        joinDate: @escaping @MainActor () -> Date? = { Auth.auth().currentUser?.metadata.creationDate },
        applyCreated: @escaping @MainActor (ModelContext, [Workout]) throws -> Void = { context, workouts in
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: context,
                mutation: .created(workouts.map(LeaderboardWorkoutSnapshot.init(workout:))),
                newWorkouts: workouts,
                changedWorkouts: workouts
            )
        },
        isUpdateRequired: @escaping @MainActor () -> Bool = { AppVersionGateState.shared.isUpdateRequired },
        now: @escaping @MainActor () -> Date = Date.init,
        observerCompletionBound: Duration = .seconds(25)
    ) {
        self.reader = reader
        self.authorization = authorization
        self.settings = settings
        self.notifier = notifier
        self.remover = remover
        self.featureFlags = featureFlags
        self.sessionWorkGate = sessionWorkGate
        self.currentUserID = currentUserID
        self.joinDate = joinDate
        self.applyCreated = applyCreated
        self.isUpdateRequired = isUpdateRequired
        self.now = now
        self.observerCompletionBound = observerCompletionBound
    }

    // MARK: - Lifecycle

    /// Points the service at the store and loads what it shows. Does no Health work and no
    /// history-sized query: a bounded count and one single-row read.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        reloadSettings()
        refreshDerivedState()
    }

    /// Everything a foreground or an authenticated bootstrap asks of import: configure, listen for
    /// new workouts, and run a pass. Cheap for a climber who never connected: the connection
    /// state is read before any Health call.
    func resume(modelContext: ModelContext) {
        configure(modelContext: modelContext)
        Task {
            // The connection state is read before anything touches Health, and a launch that has
            // not heard Health's answer yet reads as not connected. Ask first.
            await authorization.refreshAuthorizationRequestStatus()
            await syncNow()
        }
    }

    /// Called by the authenticated bootstrap once the ownership gate allowed this climber and their
    /// climbs came back from the cloud, so a first pass on this device can tell what it already has.
    func confirmCloudClimbsRestored(for userID: String) {
        cloudRestoreConfirmedUserID = userID
    }

    func cancelInFlightWork() {
        cloudRestoreConfirmedUserID = nil
        passTask?.cancel()
        passTask = nil
        rerunRequested = false
        stopObserving()
        homeNotice = nil
        badgeCount = 0
        quickEditRequest = nil
    }

    func drainInFlightWork() async {
        await passTask?.value
    }

    // MARK: - Gates

    /// Whether Ascend may look at Health for this climber right now.
    ///
    /// Read before any Health call, and every reason it can fail is a deferral: nothing is dropped
    /// and the anchor is not advanced, so the first pass after the reason clears reads everything
    /// that arrived meanwhile.
    var canImport: Bool {
        // A build the operator retired does not keep writing climbs behind a screen the climber
        // cannot leave: the lockout refuses the binary, not just its UI.
        guard modelContext != nil,
              !sessionWorkGate.isSuspended,
              !isUpdateRequired(),
              currentUserID() != nil,
              joinDate() != nil,
              reader.isHealthDataAvailable,
              authorization.importConnectionState == .connected else {
            return false
        }
        return RemoteFeatureGate.allows(
            .appleHealthImport,
            path: "AppleHealthImportService",
            store: featureFlags
        )
    }

    /// Whether the climber has connected Health in a way that lets import read workouts.
    var isConnected: Bool {
        authorization.importConnectionState == .connected
    }

    /// What the Climb sheet's Health button says, or nil when import is not on offer at all: a
    /// device with no Health, or the kill switch off.
    var entry: AppleHealthEntry? {
        switch offeredImportConnectionState {
        case nil, .unavailable:
            return nil
        case .neverConnected, .revoked:
            return .connect
        case .connected:
            return .viewImports(badge: isAutoImportEnabled ? 0 : badgeCount)
        }
    }

    /// Whether import can read workouts, or nil when import is not on offer at all: a device with
    /// no Health, or the kill switch off.
    var offeredImportConnectionState: AppleHealthConnectionState? {
        guard reader.isHealthDataAvailable, featureFlags.isEnabled(.appleHealthImport) else { return nil }
        return authorization.importConnectionState
    }

    // MARK: - Settings

    func setAutoImportEnabled(_ isEnabled: Bool) async {
        guard let userID = currentUserID() else { return }
        settings.setAutoImportEnabled(isEnabled, for: userID)
        isAutoImportEnabled = isEnabled
        if isEnabled {
            // The climber just asked for workouts to import themselves. What already waits is
            // theirs too, and leaving it under a switch that now says "imported for you" would be
            // the screen contradicting itself. Not announced: they are looking at it.
            _ = await importWaiting(announcing: [])
        }
        refreshDerivedState()
    }

    /// Opening Imports empties the badge, whether or not anything gets imported.
    func markImportsViewed() {
        guard let userID = currentUserID() else { return }
        settings.setImportsLastViewedAt(now(), for: userID)
        refreshDerivedState()
    }

    // MARK: - Discovery

    /// Reads Health from the persisted anchor and files what is new. When auto-import is on, also
    /// imports everything waiting.
    @discardableResult
    func syncNow() async -> Bool {
        guard canImport else { return false }
        startObservingIfPossible()

        if let passTask {
            // Another caller's pass is already reading. Ask it to go round once more instead of
            // starting a second read the first one would race.
            rerunRequested = true
            await passTask.value
            return true
        }

        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.rerunRequested = false
                await self.runPass(importsAutomatically: self.isAutoImportEnabled)
            } while self.rerunRequested && !Task.isCancelled
        }
        passTask = task
        await task.value
        passTask = nil
        return true
    }

    /// The pass the Connect flow runs before the climber has chosen how to import: files what
    /// Health holds and imports nothing, so the choice screen can say what it found.
    @discardableResult
    func discoverWithoutImporting() async -> Int {
        guard canImport else { return 0 }
        startObservingIfPossible()
        if let passTask { await passTask.value }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPass(importsAutomatically: false)
        }
        passTask = task
        await task.value
        passTask = nil
        return (try? ledger()?.notImportedCount()) ?? 0
    }

    private func runPass(importsAutomatically: Bool) async {
        guard let modelContext, let userID = currentUserID(), let joinDate = joinDate() else { return }
        let storedAnchor = settings.anchorData(for: userID)
        let isBackfill = storedAnchor == nil
        // A device with no anchor reads every workout since joining. Until this climber's climbs
        // have come back from the cloud in this session, the climbs that already carry those
        // workouts are not here to stop them, and each would import a second time. Deferred, not
        // dropped: the bootstrap that finishes the restore runs the pass again.
        guard !isBackfill || cloudRestoreConfirmedUserID == userID else { return }

        let changes: HealthWorkoutChanges
        do {
            changes = try await reader.changes(since: storedAnchor, startingOnOrAfter: joinDate)
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "apple_health_import_read_failed",
                level: .warning,
                details: ["error": String(describing: type(of: error))]
            )
            return
        }
        // The climber can sign out, or Health can be switched off, while the read is out.
        guard !Task.isCancelled, currentUserID() == userID, canImport else { return }

        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        var discovered: [String] = []
        do {
            for snapshot in changes.added {
                if let record = try ingest(snapshot, joinDate: joinDate, ledger: ledger) {
                    discovered.append(record.workoutUUID)
                }
            }
            try modelContext.save()
        } catch {
            // Nothing was recorded, so the anchor stays where it was and the same workouts are
            // read again next time.
            modelContext.rollback()
            AppDiagnosticsRecorder.shared.record(
                "apple_health_import_ledger_save_failed",
                level: .error,
                details: ["error": String(describing: type(of: error))]
            )
            return
        }
        settings.setAnchorData(changes.anchorData, for: userID)

        if importsAutomatically {
            // A workout found on the first pass is history. Announcing it would be a notification
            // for something that happened last month.
            let announced: Set<String> = isBackfill ? [] : Set(discovered)
            _ = await importWaiting(announcing: announced)
        }
        refreshDerivedState()
    }

    /// Files one workout, or returns nil when it is already known or is not a climb.
    private func ingest(
        _ snapshot: HealthWorkoutSnapshot,
        joinDate: Date,
        ledger: HealthWorkoutLedger
    ) throws -> HealthWorkoutRecord? {
        guard snapshot.startDate >= joinDate,
              AppleHealthImportPolicy.isImportableDuration(snapshot.duration) else {
            return nil
        }

        let uuid = snapshot.uuid.uuidString
        if let existing = try ledger.record(forUUID: uuid) {
            if existing.state == .notImported {
                existing.updateMeasurements(from: snapshot)
            }
            return nil
        }

        let record = HealthWorkoutRecord(snapshot: snapshot, discoveredAt: now())
        if let climb = try ledger.climb(withHealthKitUUID: uuid) {
            // A climb restored from the cloud already carries this workout. Remember that, so the
            // workout is not offered a second time.
            record.state = .imported
            record.importedWorkoutID = climb.id
            record.resolvedAt = now()
            ledger.modelContext.insert(record)
            return nil
        }
        if try ledger.overlappingLiveClimb(start: snapshot.startDate, end: snapshot.endDate) != nil {
            record.state = .overlapsLiveClimb
            record.resolvedAt = now()
            ledger.modelContext.insert(record)
            return nil
        }

        ledger.modelContext.insert(record)
        return record
    }

    // MARK: - Importing

    /// Imports one workout or several. Creates every climb through the same pipeline a saved climb
    /// takes, so streak, records, Best Efforts and the boards all see it. Never opens a sheet.
    @discardableResult
    func importRecords(withUUIDs uuids: [String]) async -> ImportBatch {
        guard let modelContext else { return ImportBatch(recordUUIDs: [], workoutIDs: []) }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        let records = uuids.compactMap { try? ledger.record(forUUID: $0) }
        let batch = await importRecords(records, announcing: [])
        refreshDerivedState()
        return batch
    }

    private func importWaiting(announcing announced: Set<String>) async -> ImportBatch {
        guard let ledger = ledger(), let waiting = try? ledger.notImported() else {
            return ImportBatch(recordUUIDs: [], workoutIDs: [])
        }
        return await importRecords(waiting, announcing: announced)
    }

    /// Every path that creates a climb from Health ends here, so the kill switch is read here.
    private func importRecords(_ records: [HealthWorkoutRecord], announcing announced: Set<String>) async -> ImportBatch {
        guard let modelContext, RemoteFeatureGate.allows(
            .appleHealthImport,
            path: "AppleHealthImportService.import",
            store: featureFlags
        ) else {
            return ImportBatch(recordUUIDs: [], workoutIDs: [])
        }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        var created: [(workout: Workout, announces: Bool)] = []
        var importedUUIDs: [String] = []

        for record in records where record.state == .notImported {
            // The workout's statistics can land after the workout itself, so the numbers are read
            // again at the moment they are about to become a climb. A workout Health no longer
            // has keeps the numbers it was found with.
            if let uuid = UUID(uuidString: record.workoutUUID),
               let fresh = try? await reader.snapshot(for: uuid) {
                record.updateMeasurements(from: fresh)
            }
            guard record.state == .notImported else { continue }

            if let climb = try? ledger.climb(withHealthKitUUID: record.workoutUUID) {
                record.state = .imported
                record.importedWorkoutID = climb.id
                record.resolvedAt = now()
                continue
            }
            let overlappingLiveClimb = try? ledger.overlappingLiveClimb(start: record.startDate, end: record.endDate)
            if overlappingLiveClimb != nil {
                record.state = .overlapsLiveClimb
                record.resolvedAt = now()
                continue
            }
            // A session still running, or waiting to be recovered, will save the live climb that
            // covers this workout. It waits until then, and the import after that files it.
            if (try? ledger.overlapsUnsavedLiveSession(start: record.startDate, end: record.endDate)) != false {
                continue
            }

            let workout = HealthImportedClimb.makeWorkout(from: record)
            modelContext.insert(workout)
            let announces = announced.contains(record.workoutUUID)
            record.state = .imported
            record.importedWorkoutID = workout.id
            record.resolvedAt = now()
            record.homeNoticePending = announces
            created.append((workout, announces))
            importedUUIDs.append(record.workoutUUID)
        }

        do {
            try modelContext.save()
        } catch {
            // Nothing landed: the climbs were only inserted, and the ledger rows only edited.
            modelContext.rollback()
            AppDiagnosticsRecorder.shared.record(
                "apple_health_import_save_failed",
                level: .error,
                details: ["error": String(describing: type(of: error))]
            )
            return ImportBatch(recordUUIDs: [], workoutIDs: [])
        }
        do {
            try applyCreated(modelContext, created.map(\.workout))
        } catch {
            // The climbs are saved; only the derived surfaces missed the news, and the next
            // rebuild catches them up. The import itself stands and can still be undone.
            AppDiagnosticsRecorder.shared.record(
                "apple_health_import_derived_refresh_failed",
                level: .warning,
                details: ["error": String(describing: type(of: error))]
            )
        }

        for (workout, announces) in created where announces {
            await notifier.climbImported(workoutID: workout.id, steps: workout.recordedSteps)
        }
        refreshDerivedState()
        return ImportBatch(recordUUIDs: importedUUIDs, workoutIDs: created.map(\.workout.id))
    }

    /// Takes an import back: the climbs are deleted and the workouts return to Not imported.
    func undo(_ batch: ImportBatch) async {
        guard let modelContext else { return }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)

        var climbs: [Workout] = []
        for id in batch.workoutIDs {
            if let climb = try? ledger.climb(withID: id) { climbs.append(climb) }
        }
        for uuid in batch.recordUUIDs {
            guard let record = try? ledger.record(forUUID: uuid) else { continue }
            record.state = .notImported
            record.importedWorkoutID = nil
            record.resolvedAt = nil
            record.homeNoticePending = false
        }

        do {
            try await remover.remove(climbs, modelContext: modelContext, fallbackUserID: currentUserID())
            try modelContext.save()
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "apple_health_import_undo_failed",
                level: .error,
                details: ["error": String(describing: type(of: error))]
            )
        }
        refreshDerivedState()
    }

    // MARK: - Skipping and removing

    /// A swipe on a Not imported row. The workout never comes back, in either mode.
    func skip(recordUUID: String) {
        guard let modelContext, let record = try? HealthWorkoutLedger(modelContext: modelContext).record(forUUID: recordUUID),
              record.state == .notImported else { return }
        record.state = .skipped
        record.resolvedAt = now()
        try? modelContext.save()
        refreshDerivedState()
    }

    /// Remove this climb: deletes the imported climb and marks its workout skipped for good.
    func removeImportedClimb(workoutID: UUID) async {
        guard let modelContext else { return }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        guard let climb = try? ledger.climb(withID: workoutID) else { return }

        ledger.markSkippedForDeletedClimbs([climb], resolvedAt: now())
        do {
            try await remover.remove([climb], modelContext: modelContext, fallbackUserID: currentUserID())
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "apple_health_import_remove_failed",
                level: .error,
                details: ["error": String(describing: type(of: error))]
            )
        }
        if quickEditRequest?.workoutID == workoutID { quickEditRequest = nil }
        refreshDerivedState()
    }

    // MARK: - Quick edit and the Home strip

    func requestQuickEdit(workoutID: UUID) {
        quickEditRequest = QuickEditRequest(workoutID: workoutID)
        retireHomeNotice()
    }

    /// Retires the strip: the climber opened the quick edit, finished it, or it has aged out.
    func retireHomeNotice() {
        guard let modelContext else { return }
        try? HealthWorkoutLedger(modelContext: modelContext).clearPendingNotices()
        homeNotice = nil
    }

    /// Re-reads the two things Home draws from the ledger. A bounded count and single-row reads: the
    /// notice names what the climb holds now, since the record stops updating once it is imported.
    func refreshDerivedState() {
        guard let modelContext, let userID = currentUserID() else {
            badgeCount = 0
            homeNotice = nil
            return
        }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)

        if isAutoImportEnabled {
            badgeCount = 0
        } else {
            badgeCount = (try? ledger.badgeCount(
                now: now(),
                importsLastViewedAt: settings.importsLastViewedAt(for: userID)
            )) ?? 0
        }

        if let record = try? ledger.pendingNoticeRecord(now: now()),
           let workoutID = record.importedWorkoutID {
            let climb = try? ledger.climb(withID: workoutID)
            homeNotice = HomeNotice(
                workoutID: workoutID,
                startDate: record.startDate,
                steps: climb.map(\.recordedSteps) ?? record.importableSteps,
                duration: climb?.duration ?? record.durationSeconds
            )
        } else {
            homeNotice = nil
        }
    }

    // MARK: - Observing

    /// Registers for new workouts, including while the app is closed. Idempotent.
    func startObservingIfPossible() {
        guard !isObserving, canImport else { return }
        isObserving = true
        let bound = observerCompletionBound

        reader.startObserving { [weak self] completion in
            // HealthKit waits for `completion`, so it is guaranteed on every path: after the pass,
            // or when the bound runs out, whichever is first. The reader ignores a second call.
            let watchdog = Task {
                try? await Task.sleep(for: bound)
                completion()
            }
            Task { @MainActor in
                await self?.syncNow()
                watchdog.cancel()
                completion()
            }
        }
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        reader.stopObserving()
    }

    // MARK: - Helpers

    private func reloadSettings() {
        guard let userID = currentUserID() else {
            isAutoImportEnabled = true
            return
        }
        isAutoImportEnabled = settings.isAutoImportEnabled(for: userID)
    }

    private func ledger() -> HealthWorkoutLedger? {
        modelContext.map(HealthWorkoutLedger.init(modelContext:))
    }
}
