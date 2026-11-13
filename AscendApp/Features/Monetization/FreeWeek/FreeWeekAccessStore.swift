import Foundation
import Observation

/// The device's one answer to "is this account on its free week".
///
/// Owned by ``MonetizationManager``, which hands it every identity change, so it holds exactly one
/// account's record and drops it the moment that account signs out. The server decides everything
/// that matters - whether a week exists and when it ends - and this store only mirrors it: a cached
/// copy so a running week opens the app offline, one bounded read when nothing is cached, and the
/// `startFreeWeek` call the app-access gate makes after every paid offer is declined.
///
/// With `free_week_after_decline_enabled` off the store reads nothing, grants nothing and reports
/// no week, a running one included. That is deliberate: the switch is the only undo an iOS binary
/// has, so off has to mean the gate behaves exactly as it did before this existed. Nothing is
/// deleted, and turning the switch back on honours whatever is left of a week.
@MainActor
@Observable
final class FreeWeekAccessStore {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private(set) var record: FreeWeekRecordState = .unknown
    private(set) var isEnabled: Bool
    private(set) var userID: String?
    /// Bumped whenever the clock may have crossed the end of the week, so everything derived from
    /// "is it still running" is re-derived without a view polling the time.
    private var clockRevision: UInt = 0

    @ObservationIgnored private let makeReader: @MainActor () -> any FreeWeekRecordReading
    @ObservationIgnored private let makeGranter: @MainActor () -> any FreeWeekGranting
    @ObservationIgnored private let cache: FreeWeekRecordCache
    @ObservationIgnored private let featureFlags: RemoteFeatureFlagStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let readDeadline: Duration
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lapseTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var flagObserver: (any NSObjectProtocol)?

    init(
        reader: @escaping @MainActor () -> any FreeWeekRecordReading = { FirestoreFreeWeekRecordReader() },
        granter: @escaping @MainActor () -> any FreeWeekGranting = { FunctionsFreeWeekGranter() },
        cache: FreeWeekRecordCache = FreeWeekRecordCache(),
        featureFlags: RemoteFeatureFlagStore = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        readDeadline: Duration = .seconds(6),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        makeReader = reader
        makeGranter = granter
        self.cache = cache
        self.featureFlags = featureFlags
        self.now = now
        self.readDeadline = readDeadline
        self.sleep = sleep
        isEnabled = featureFlags.isEnabled(.freeWeekAfterDecline)
        flagObserver = NotificationCenter.default.addObserver(
            forName: .remoteFeatureFlagsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.featureFlagsDidChange()
            }
        }
    }

    deinit {
        if let flagObserver {
            NotificationCenter.default.removeObserver(flagObserver)
        }
    }

    /// The running week, or `nil` when there is none or the feature is off.
    var liveGrant: FreeWeekGrant? {
        _ = clockRevision
        guard isEnabled, case .granted(let grant) = record, grant.isLive(at: now()) else {
            return nil
        }

        return grant
    }

    /// Whether this account's week has been given and is over.
    var hasSpentWeek: Bool {
        _ = clockRevision
        guard isEnabled, case .granted(let grant) = record else { return false }
        return !grant.isLive(at: now())
    }

    var routingAccess: FreeWeekRoutingAccess {
        guard isEnabled, userID != nil else { return .none }
        if liveGrant != nil { return .live }
        return record == .unknown ? .unresolved : .none
    }

    /// Whole days left in a running week, for the Settings row.
    var daysLeft: Int? {
        liveGrant?.daysLeft(at: now())
    }

    /// Adopts the signed-in account, or drops everything when there is none.
    func setUser(_ newUserID: String?) {
        guard newUserID != userID else { return }

        refreshTask?.cancel()
        refreshTask = nil
        lapseTask?.cancel()
        lapseTask = nil
        userID = newUserID

        guard let newUserID, let cached = cache.grant(for: newUserID) else {
            record = .unknown
            resolveIfNeeded()
            return
        }

        record = .granted(cached)
        scheduleLapse(for: cached)
    }

    /// Re-reads the clock, and asks the server again when the last answer was no answer.
    ///
    /// Called on launch and on every foreground. A suspended app is not a reliable alarm clock, so
    /// the timer that ends a week on screen cannot be the only thing that ends it.
    func reevaluate() {
        clockRevision &+= 1
        if case .granted(let grant) = record {
            scheduleLapse(for: grant)
        }
        // An unanswered read is asked again in place. It is deliberately not moved back to
        // `.unknown` first: that would pull a climber off the paywall they are reading and onto
        // the resolving screen on every foreground of a phone with no signal.
        guard isEnabled, userID != nil, refreshTask == nil,
              record == .unknown || record == .unavailable else { return }

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    /// Reads this account's record from the server, bounded by the read deadline.
    func refresh() async {
        guard isEnabled, let userID else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(for: userID)
        }
        refreshTask = task
        await task.value
    }

    /// Starts the week, retrying a failed call once.
    ///
    /// A refusal is an answer and is never retried. Only a call that failed outright, or answered
    /// in a shape this build does not understand, gets the second attempt.
    func startFreeWeek() async -> FreeWeekStartOutcome {
        guard isEnabled, let userID else { return .failed }

        for _ in 0..<2 {
            let response: FreeWeekGrantResponse
            do {
                response = try await makeGranter().startFreeWeek()
            } catch {
                continue
            }
            guard self.userID == userID else { return .failed }

            switch response {
            case .granted(let grant):
                adopt(grant, for: userID)
                return .started(grant)
            case .alreadyUsed(let grant):
                adopt(grant ?? Self.spentWeek, for: userID)
                return .alreadyUsed
            case .paidActive:
                return .paidActive
            case .disabled:
                return .failed
            case .unrecognized:
                continue
            }
        }

        return .failed
    }

    /// The onboarding this device started the week from, when it was this device that started it.
    var startedFlowVersion: String? {
        userID.flatMap(cache.flowVersion(for:))
    }

    /// Remembers which onboarding led to the week, for the events that arrive days later.
    func rememberStartedFlowVersion(_ flowVersion: String) {
        guard let userID else { return }
        cache.storeFlowVersion(flowVersion, for: userID)
    }

    /// Whether the "week ended, gate shown" event should be sent now. True once per account on
    /// this device, and only for an account whose week is really over.
    func claimExpiredGateReport() -> Bool {
        guard hasSpentWeek, let userID else { return false }
        return cache.claimExpiredGateReport(for: userID)
    }

    private func featureFlagsDidChange() {
        let enabled = featureFlags.isEnabled(.freeWeekAfterDecline)
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        resolveIfNeeded()
    }

    /// The route holds on `.unresolved`, so anything that produces that state has to start the read
    /// that ends it. Every path into `.unknown` comes through here.
    private func resolveIfNeeded() {
        guard isEnabled, userID != nil, record == .unknown, refreshTask == nil else { return }

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    private func performRefresh(for userID: String) async {
        let result = await readWithDeadline(userID: userID)
        guard self.userID == userID else { return }

        refreshTask = nil
        switch result {
        case .success(let grant?):
            adopt(grant, for: userID)
        case .success(nil):
            record = .absent
        case .failure:
            // A week the device already knows about is not un-known by a failed read.
            if case .granted = record { return }
            record = .unavailable
        }
    }

    private func adopt(_ grant: FreeWeekGrant, for userID: String) {
        record = .granted(grant)
        cache.store(grant, for: userID)
        scheduleLapse(for: grant)
    }

    private func scheduleLapse(for grant: FreeWeekGrant) {
        lapseTask?.cancel()
        lapseTask = nil
        let remaining = grant.expiresAt.timeIntervalSince(now())
        guard remaining > 0 else { return }

        lapseTask = Task { @MainActor [weak self, sleep] in
            do {
                try await sleep(.seconds(remaining))
            } catch {
                return
            }
            self?.clockRevision &+= 1
        }
    }

    /// The Firestore SDK owns the read's own retry, but not a promise to return. A route is held
    /// on this answer, so it gets a wall clock: whichever of the read and the deadline lands first
    /// is the answer, and the loser is ignored.
    private func readWithDeadline(userID: String) async -> Result<FreeWeekGrant?, any Error> {
        let reader = makeReader()
        let race = ReadRace()

        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { @MainActor in
                do {
                    race.finish(.success(try await reader.readRecord(userID: userID)))
                } catch {
                    race.finish(.failure(error))
                }
            }
            Task { @MainActor [sleep, readDeadline] in
                try? await sleep(readDeadline)
                race.finish(.failure(ReadDeadlineExceeded()))
            }
        }
    }

    /// A week the server says was given but whose dates it could not supply. Over, by definition.
    private static let spentWeek = FreeWeekGrant(grantedAt: .distantPast, expiresAt: .distantPast)
}

private struct ReadDeadlineExceeded: Error {}

@MainActor
private final class ReadRace {
    var continuation: CheckedContinuation<Result<FreeWeekGrant?, any Error>, Never>?

    func finish(_ result: Result<FreeWeekGrant?, any Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
