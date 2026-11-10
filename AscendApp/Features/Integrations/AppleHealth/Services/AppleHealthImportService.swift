import Foundation
import Observation
import SwiftData
@preconcurrency import FirebaseAuth

/// The three Apple Health states the Climb sheet's right-hand button tells apart.
enum AppleHealthEntry: Equatable {
    /// Not connected, or connected before import and never asked for workouts: Connect Health.
    case connect
    /// Connected. `badge` is the red count: zero with auto-import on, where nothing ever waits.
    case viewImports(badge: Int)
}

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
/// ## Steps
///
/// A workout's steps are its own, else the steps Health counted over its window, else unknown
/// (`HealthWorkoutStepRule`). Every read here goes through that rule before the workout is filed.
///
/// ## A live climb wins
///
/// A workout whose window overlaps an Ascend live climb by a minute is not a second climb. It is
/// filed as `overlapsLiveClimb` and that is the end of it: never imported, never merged into the
/// live climb, and never put in front of the climber. The live climb is the climb.
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
    /// From the Connect flow's look at Health until the climber picks how workouts import. Passes
    /// only file workouts meanwhile, or Let me choose would have nothing left to choose.
    private(set) var isImportChoicePending = false
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
    @ObservationIgnored private let skipReporter: any HealthWorkoutSkipReporting
    @ObservationIgnored private let featureFlags: RemoteFeatureFlagStore
    @ObservationIgnored private let sessionWorkGate: AuthenticatedBootstrapCoordinator
    @ObservationIgnored private let sessionStore: AccountSessionStore
    @ObservationIgnored private let currentUserID: @MainActor () -> String?
    @ObservationIgnored private let joinDate: @MainActor () -> Date?
    @ObservationIgnored private let applyCreated: @MainActor (ModelContext, [Workout]) throws -> Void
    @ObservationIgnored private let isUpdateRequired: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let observerCompletionBound: Duration

    // MARK: Private state

    @ObservationIgnored private var modelContext: ModelContext?
    /// Held until the pass ends, through cancellation too, so a drain can wait for it.
    @ObservationIgnored private var passTask: Task<Void, Never>?
    /// Imports the climber asked for, which run outside a pass and must be drained like one.
    @ObservationIgnored private var requestedImports: [UUID: Task<ImportBatch, Never>] = [:]
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
        skipReporter: any HealthWorkoutSkipReporting = HealthWorkoutSkipReporter.shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        sessionWorkGate: AuthenticatedBootstrapCoordinator = .shared,
        sessionStore: AccountSessionStore = .shared,
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
        self.skipReporter = skipReporter
        self.featureFlags = featureFlags
        self.sessionWorkGate = sessionWorkGate
        self.sessionStore = sessionStore
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
        requestedImports.values.forEach { $0.cancel() }
        rerunRequested = false
        isImportChoicePending = false
        stopObserving()
        homeNotice = nil
        badgeCount = 0
        quickEditRequest = nil
    }

    func drainInFlightWork() async {
        await passTask?.value
        for task in Array(requestedImports.values) {
            _ = await task.value
        }
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
              localStoreBelongsToCurrentClimber,
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

    private var localStoreBelongsToCurrentClimber: Bool {
        guard let userID = currentUserID() else { return false }
        return sessionStore.localDataOwnerUserId == userID
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

    /// Whether the choice screen has to come back: the app ended on it before the climber picked.
    var needsImportChoice: Bool {
        isImportChoicePending && offeredImportConnectionState == .connected
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
        settings.setImportChoicePending(false, for: userID)
        isImportChoicePending = false
        settings.setAutoImportEnabled(isEnabled, for: userID)
        isAutoImportEnabled = isEnabled
        if isEnabled {
            // The climber just asked for workouts to import themselves. What already waits is
            // theirs too, and leaving it under a switch that now says "imported for you" would be
            // the screen contradicting itself. Not announced: they are looking at it.
            _ = await trackingRequestedImport { await self.importWaiting(announcing: []) }
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

        // A cancelled pass belongs to a session that ended, so a new one waits it out and starts
        // its own rather than joining it.
        if let passTask, passTask.isCancelled {
            await passTask.value
            guard canImport else { return false }
        }
        if let passTask {
            // Another caller's pass is already reading. Ask it to go round once more instead of
            // starting a second read the first one would race.
            rerunRequested = true
            await passTask.value
            return true
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.passTask = nil }
            repeat {
                self.rerunRequested = false
                await self.runPass(importsAutomatically: self.importsAutomatically)
            } while self.rerunRequested && !Task.isCancelled
        }
        passTask = task
        await task.value
        return true
    }

    /// The pass the Connect flow runs before the climber has chosen how to import: files what
    /// Health holds and imports nothing, so the choice screen can say what it found.
    @discardableResult
    func discoverWithoutImporting() async -> Int {
        if let userID = currentUserID() {
            settings.setImportChoicePending(true, for: userID)
            isImportChoicePending = true
        }
        guard canImport else { return 0 }
        startObservingIfPossible()
        while let passTask { await passTask.value }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.passTask = nil }
            await self.runPass(importsAutomatically: false)
        }
        passTask = task
        await task.value
        return waitingWorkoutCount
    }

    var waitingWorkoutCount: Int {
        (try? ledger()?.notImportedCount()) ?? 0
    }

    private var importsAutomatically: Bool {
        guard let userID = currentUserID() else { return false }
        return isAutoImportEnabled && !settings.isImportChoicePending(for: userID)
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
        let climbs = await stepResolvedClimbs(in: changes.added.filter { $0.startDate >= joinDate })
        // The climber can sign out, or Health can be switched off, while the reads are out.
        guard !Task.isCancelled, currentUserID() == userID, canImport else { return }

        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        var discovered: [String] = []
        do {
            for snapshot in climbs {
                if case .discovered(let record) = try file(snapshot, ledger: ledger) {
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

    /// The workouts of a read that can be climbs, with their steps settled by the step rule.
    ///
    /// A workout that cannot be a climb - shorter than a second, longer than a day - is reported
    /// as passed over and goes no further.
    private func stepResolvedClimbs(in snapshots: [HealthWorkoutSnapshot]) async -> [HealthWorkoutSnapshot] {
        var climbs: [HealthWorkoutSnapshot] = []
        for snapshot in snapshots {
            if AppleHealthImportPolicy.isImportableDuration(snapshot.duration) {
                climbs.append(snapshot)
            } else {
                skipReporter.report(HealthWorkoutSkip(snapshot, reason: .duration))
            }
        }
        return await HealthWorkoutStepRule.resolve(climbs, using: reader)
    }

    /// What filing a workout in the ledger found.
    private enum Filing {
        /// A workout the ledger had never met, now waiting to be imported.
        case discovered(HealthWorkoutRecord)
        /// A workout still waiting from an earlier pass.
        case alreadyWaiting(HealthWorkoutRecord)
        /// Nothing to import: it already is a climb, or an Ascend live climb covers it.
        case settled
    }

    /// The ledger half of discovery, shared by the pass and the history backfill so one workout is
    /// recognised the same way whichever of them meets it first.
    private func file(_ snapshot: HealthWorkoutSnapshot, ledger: HealthWorkoutLedger) throws -> Filing {
        let uuid = snapshot.uuid.uuidString
        if let existing = try ledger.record(forUUID: uuid) {
            guard existing.state == .notImported else { return .settled }
            existing.updateMeasurements(from: snapshot)
            return .alreadyWaiting(existing)
        }

        let record = HealthWorkoutRecord(snapshot: snapshot, discoveredAt: now())
        if let climb = try ledger.climb(withHealthKitUUID: uuid) {
            // A climb restored from the cloud already carries this workout. Remember that, so the
            // workout is not offered a second time.
            record.state = .imported
            record.importedWorkoutID = climb.id
            record.resolvedAt = now()
            ledger.modelContext.insert(record)
            return .settled
        }
        if try ledger.overlappingLiveClimb(start: snapshot.startDate, end: snapshot.endDate) != nil {
            // The live climb is the climb. Terminal: nothing imports, merges or asks about it.
            record.state = .overlapsLiveClimb
            record.resolvedAt = now()
            ledger.modelContext.insert(record)
            skipReporter.report(HealthWorkoutSkip(snapshot, reason: .overlapsLiveClimb))
            return .settled
        }

        ledger.modelContext.insert(record)
        return .discovered(record)
    }

    // MARK: - History

    /// Brings in the stair workouts Health held before this climber joined, once, because the
    /// climber asked for them on screen 07a ("ADD TO MY HISTORY").
    ///
    /// The pass reads from the join date on, so this is the only way older workouts arrive. They
    /// go through the same ledger and the same import path as any other workout, as `.appleHealth`
    /// climbs, and arrive off the boards (`HealthImportedClimb.makeWorkout`): they fill history,
    /// personal bests and streaks and never a leaderboard, which the server agrees with from
    /// Auth's creation time (`startedBeforeAccount`). A workout already imported or skipped is left
    /// as it is, so this never files one twice and never brings back one the climber removed.
    ///
    /// It never touches the pass's anchor, announces nothing and opens nothing: the climber saw
    /// the screen that promised it.
    ///
    /// - Parameter workoutIDs: The workouts 07a showed, which is all the climber agreed to. There is
    ///   no "everything" form: a caller that forgot the list would import what the climber never saw.
    /// - Returns: Whether the history landed. False means something deferred it - the switch, a
    ///   gate the pass shares, a failed read or save - and nothing was lost: running it again
    ///   files and imports whatever is still waiting.
    @discardableResult
    func importHistory(matching workoutIDs: Set<String>) async -> Bool {
        guard RemoteFeatureGate.allows(
            .appleHealthHistoryImport,
            path: "AppleHealthImportService.importHistory",
            store: featureFlags
        ) else {
            return false
        }
        // A launch that has not heard Health's answer yet reads as not connected. Ask first.
        await authorization.refreshAuthorizationRequestStatus()
        // The same gates as a pass, and the same wait for the cloud restore: a climb restored from
        // the account is the only thing that stops its own workout importing a second time.
        guard canImport, let modelContext, let userID = currentUserID(), let joinedAt = joinDate(),
              cloudRestoreConfirmedUserID == userID else {
            return false
        }

        let found: HealthWorkoutChanges
        do {
            found = try await reader.changes(since: nil, startingOnOrAfter: .distantPast)
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "apple_health_history_read_failed",
                level: .warning,
                details: ["error": String(describing: type(of: error))]
            )
            return false
        }
        let asked = await stepResolvedClimbs(in: found.added.filter {
            $0.startDate < joinedAt && workoutIDs.contains($0.uuid.uuidString)
        })
        guard !Task.isCancelled, currentUserID() == userID, canImport else { return false }

        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        var waiting: [HealthWorkoutRecord] = []
        do {
            for snapshot in asked {
                switch try file(snapshot, ledger: ledger) {
                case .discovered(let record), .alreadyWaiting(let record):
                    waiting.append(record)
                case .settled:
                    break
                }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AppDiagnosticsRecorder.shared.record(
                "apple_health_history_ledger_save_failed",
                level: .error,
                details: ["error": String(describing: type(of: error))]
            )
            return false
        }

        let records = waiting
        _ = await trackingRequestedImport { await self.importRecords(records, announcing: []) }
        refreshDerivedState()
        return records.allSatisfy { $0.state != .notImported }
    }

    /// What Integrations' Import older workouts has to offer: the stair workouts Health holds from
    /// before this climber joined that are not climbs yet and were never turned away, with their
    /// steps settled by the step rule. Read-only, like 07a's look: nothing is filed.
    ///
    /// - Returns: Nil when Health cannot be read right now, which a caller says as "try again" and
    ///   never as "nothing to import".
    func olderWorkouts() async -> [HealthWorkoutSnapshot]? {
        guard featureFlags.isEnabled(.appleHealthHistoryImport) else { return nil }
        await authorization.refreshAuthorizationRequestStatus()
        guard canImport, let modelContext, let userID = currentUserID(), let joinedAt = joinDate(),
              let found = try? await reader.changes(since: nil, startingOnOrAfter: .distantPast) else {
            return nil
        }
        guard !Task.isCancelled, currentUserID() == userID else { return nil }

        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        let open = found.added.filter { snapshot in
            guard snapshot.startDate < joinedAt else { return false }
            let uuid = snapshot.uuid.uuidString
            if let record = try? ledger.record(forUUID: uuid) { return record.state == .notImported }
            return (try? ledger.climb(withHealthKitUUID: uuid)) == nil
        }
        return await stepResolvedClimbs(in: open)
    }

    /// Whether Integrations offers Import older workouts: Health connected for import, and the
    /// history backfill's own switch on.
    var offersOlderWorkouts: Bool {
        offeredImportConnectionState == .connected && featureFlags.isEnabled(.appleHealthHistoryImport)
    }

    // MARK: - Importing

    /// Imports one workout or several. Creates every climb through the same pipeline a saved climb
    /// takes, so streak, records, Best Efforts and the boards all see it. Never opens a sheet.
    @discardableResult
    func importRecords(withUUIDs uuids: [String]) async -> ImportBatch {
        guard let modelContext else { return ImportBatch(recordUUIDs: [], workoutIDs: []) }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        let records = uuids.compactMap { try? ledger.record(forUUID: $0) }
        let batch = await trackingRequestedImport { await self.importRecords(records, announcing: []) }
        refreshDerivedState()
        return batch
    }

    private func trackingRequestedImport(
        _ work: @escaping @MainActor () async -> ImportBatch
    ) async -> ImportBatch {
        let id = UUID()
        let task = Task { [weak self] in
            defer { self?.requestedImports[id] = nil }
            return await work()
        }
        requestedImports[id] = task
        return await task.value
    }

    private func importWaiting(announcing announced: Set<String>) async -> ImportBatch {
        guard let ledger = ledger(), let waiting = try? ledger.notImported() else {
            return ImportBatch(recordUUIDs: [], workoutIDs: [])
        }
        return await importRecords(waiting, announcing: announced)
    }

    /// Every path that creates a climb from Health ends here, so the kill switch is read here.
    private func importRecords(_ records: [HealthWorkoutRecord], announcing announced: Set<String>) async -> ImportBatch {
        guard let modelContext, localStoreBelongsToCurrentClimber, RemoteFeatureGate.allows(
            .appleHealthImport,
            path: "AppleHealthImportService.import",
            store: featureFlags
        ) else {
            return ImportBatch(recordUUIDs: [], workoutIDs: [])
        }
        let ledger = HealthWorkoutLedger(modelContext: modelContext)
        var created: [(workout: Workout, announces: Bool)] = []
        var importedUUIDs: [String] = []
        let owner = currentUserID()

        for record in records where record.state == .notImported {
            // The workout's statistics can land after the workout itself, so the numbers are read
            // again at the moment they are about to become a climb. A workout Health no longer
            // has keeps the numbers it was found with.
            var fresh: HealthWorkoutSnapshot?
            if let uuid = UUID(uuidString: record.workoutUUID),
               let read = try? await reader.snapshot(for: uuid) {
                let resolved = await HealthWorkoutStepRule.resolve(read, using: reader)
                record.updateMeasurements(from: resolved)
                fresh = resolved
            }
            // The session can end during that read. The workouts stay waiting, and nothing of this
            // batch lands in a store that is about to be emptied or handed to the next climber.
            guard !Task.isCancelled, currentUserID() == owner else {
                modelContext.rollback()
                return ImportBatch(recordUUIDs: [], workoutIDs: [])
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
                skipReporter.report(HealthWorkoutSkip(
                    fresh ?? HealthWorkoutSnapshot(record: record),
                    reason: .overlapsLiveClimb
                ))
                continue
            }
            // A session still running, or waiting to be recovered, will save the live climb that
            // covers this workout. It waits until then, and the import after that files it.
            if (try? ledger.overlapsUnsavedLiveSession(start: record.startDate, end: record.endDate)) != false {
                continue
            }

            let workout = HealthImportedClimb.makeWorkout(from: record, accountCreatedAt: joinDate())
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
        if !created.isEmpty {
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
        }

        for (workout, announces) in created where announces && !Task.isCancelled {
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
        guard !Task.isCancelled else { return }
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
            isImportChoicePending = false
            return
        }
        isAutoImportEnabled = settings.isAutoImportEnabled(for: userID)
        isImportChoicePending = settings.isImportChoicePending(for: userID)
    }

    private func ledger() -> HealthWorkoutLedger? {
        modelContext.map(HealthWorkoutLedger.init(modelContext:))
    }
}
