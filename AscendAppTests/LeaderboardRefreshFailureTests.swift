import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// What a climber sees, and what gets recorded, when the leaderboard cannot get the server's
/// standings.
///
/// Before this, one sentence - "Showing cached data. Latest refresh failed." - covered a
/// production rules outage (2026-09-25) and a stream that dropped for five minutes with nothing
/// wrong (2026-10-03), and neither left a record on the device.
@MainActor
struct LeaderboardRefreshFailureTests {
    private static let calmLine = "Leaderboard not updated. Pull to retry."
    private static let accessLine = "Ascend couldn't confirm your access. Pull to retry."

    // MARK: - Unreachable

    @Test
    func aDroppedStreamThatComesBackOnTheQuietRetryShowsNothing() async throws {
        let board = Board(server: [.failure(Firestore.error(.unavailable)), .success([Self.stat("aaa")])])

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == nil)
        #expect(board.viewModel.isOffline == false)
        #expect(board.viewModel.leaderboardEntries.map(\.userId) == ["aaa"])
        #expect(board.standings.sources == [.server, .server])
        #expect(board.recovery.calls.isEmpty)

        let recorded = try board.onlyRecordedFailure()
        #expect(recorded.code == "leaderboard_refresh_failed")
        #expect(recorded.context == "firestore")
        #expect(recorded.severity == .warning)
        #expect(recorded.additionalInfo == [
            "failure_class": "unreachable",
            "error_domain": "FIRFirestoreErrorDomain",
            "error_code": "14",
            "forced": "true",
            "failed_attempts": "1",
            "retry_recovered": "true",
            "access_reconcile_attempted": "false",
            "resolution": "recovered",
            "seconds_since_launch": "75",
            "seconds_since_foreground": "4",
            "network": "wifi"
        ])
        #expect(try board.onlyRefreshFailedEvent() == [
            "metric": .string("climb"),
            "time_frame": .string("weekly"),
            "failure_class": .string("unreachable"),
            "error_domain": .string("FIRFirestoreErrorDomain"),
            "error_code": .int(14),
            "forced": .bool(true),
            "retry_recovered": .bool(true),
            "access_reconcile_attempted": .bool(false),
            "resolution": .string("recovered"),
            "network": .string("wifi"),
            "launch_age": .string("1m_to_10m"),
            "foreground_age": .string("under_10s")
        ])
    }

    @Test
    func aServerUnreachableTwiceShowsTheCalmLineOverTheLastBoard() async throws {
        let board = Board(
            server: [.failure(Firestore.error(.unavailable)), .failure(Firestore.error(.unavailable))],
            deviceCopy: [Self.stat("aaa")]
        )

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == Self.calmLine)
        #expect(board.viewModel.isOffline == false)
        #expect(board.viewModel.hasCachedEntries)
        #expect(board.viewModel.isLoading == false)
        // Asked, asked once more after the quiet wait, then the device's own copy.
        #expect(board.standings.sources == [.server, .server, .cache])

        let recorded = try board.onlyRecordedFailure()
        #expect(recorded.severity == .warning)
        #expect(recorded.additionalInfo?["failure_class"] == "unreachable")
        #expect(recorded.additionalInfo?["failed_attempts"] == "2")
        #expect(recorded.additionalInfo?["retry_recovered"] == "false")
        #expect(recorded.additionalInfo?["resolution"] == "stale_board")
        #expect(try board.onlyRefreshFailedEvent()["resolution"] == .string("stale_board"))
    }

    /// An ordinary load reads with the SDK's default source, which already answers from the
    /// device's copy while the stream is down. It has nothing to wait for.
    @Test
    func anOrdinaryLoadThatTimesOutIsNotMadeToWaitAndRetry() async throws {
        let board = Board(
            server: [.failure(LeaderboardTimeoutError.operationTimedOut)],
            deviceCopy: [Self.stat("aaa")]
        )

        await board.viewModel.loadLeaderboard(userId: "aaa")

        #expect(board.viewModel.errorMessage == Self.calmLine)
        #expect(board.standings.sources == [.default, .cache])
        #expect(try board.onlyRecordedFailure().additionalInfo?["forced"] == "false")
    }

    // MARK: - Refused

    /// 2026-09-25: rules refused every paid read until the grant was re-derived, and launch was
    /// the only thing that asked for that.
    @Test
    func aRefusedReadShowsTheAccessLineAndReconcilesOnce() async throws {
        let board = Board(
            server: [
                .failure(Firestore.error(.permissionDenied)),
                .failure(Firestore.error(.permissionDenied))
            ],
            deviceCopy: [Self.stat("aaa")]
        )

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == Self.accessLine)
        #expect(board.viewModel.hasCachedEntries)
        // Once, and as the climber's own request, so the client-side spacing does not swallow it.
        #expect(board.recovery.calls == [true])
        #expect(board.standings.sources == [.server, .server, .cache])

        let recorded = try board.onlyRecordedFailure()
        #expect(recorded.severity == .error)
        #expect(recorded.additionalInfo?["failure_class"] == "refused")
        #expect(recorded.additionalInfo?["error_code"] == "7")
        #expect(recorded.additionalInfo?["access_reconcile_attempted"] == "true")
        #expect(recorded.additionalInfo?["resolution"] == "stale_board")
    }

    @Test
    func aRefusalHealedByReconciliationShowsNothing() async throws {
        let board = Board(server: [
            .failure(Firestore.error(.permissionDenied)),
            .success([Self.stat("aaa")])
        ])

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == nil)
        #expect(board.viewModel.leaderboardEntries.map(\.userId) == ["aaa"])
        #expect(board.recovery.calls == [true])

        // Recovered, and still an error: the grant was missing and somebody should know.
        let recorded = try board.onlyRecordedFailure()
        #expect(recorded.severity == .error)
        #expect(recorded.additionalInfo?["retry_recovered"] == "true")
        #expect(recorded.additionalInfo?["access_reconcile_attempted"] == "true")
    }

    /// A refusal on an ordinary load reconciles too, but as background work that respects the
    /// client-side spacing.
    @Test
    func aRefusedOrdinaryLoadReconcilesWithoutClaimingTheClimberAsked() async {
        let board = Board(server: [
            .failure(Firestore.error(.permissionDenied)),
            .success([Self.stat("aaa")])
        ])

        await board.viewModel.loadLeaderboard(userId: "aaa")

        #expect(board.viewModel.errorMessage == nil)
        #expect(board.recovery.calls == [false])
    }

    /// No entitlement on the device means the refusal is the paywall working, so nothing is
    /// retried.
    @Test
    func aRefusalWithNoEntitlementToReDeriveIsNotAskedAgain() async {
        let board = Board(
            server: [.failure(Firestore.error(.permissionDenied))],
            deviceCopy: [Self.stat("aaa")],
            recoveryHeals: false
        )

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == Self.accessLine)
        #expect(board.recovery.calls == [true])
        #expect(board.standings.sources == [.server, .cache])
    }

    @Test
    func aRefusalWithNoBoardToShowStillNamesAccess() async throws {
        let board = Board(server: [
            .failure(Firestore.error(.permissionDenied)),
            .failure(Firestore.error(.permissionDenied))
        ])

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.leaderboardEntries.isEmpty)
        #expect(board.viewModel.hasCachedEntries == false)
        #expect(board.viewModel.errorMessage == Self.accessLine)
        #expect(try board.onlyRecordedFailure().additionalInfo?["resolution"] == "empty_board")
    }

    // MARK: - Unexpected

    /// A missing index (`failedPrecondition`) is a defect: same calm line for the climber,
    /// error level for whoever reads the record, and no retry that could not help.
    @Test
    func anUnexpectedFailureShowsTheCalmLineAndIsRecordedAtErrorLevel() async throws {
        let board = Board(
            server: [.failure(Firestore.error(.failedPrecondition))],
            deviceCopy: [Self.stat("aaa")]
        )

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == Self.calmLine)
        #expect(board.standings.sources == [.server, .cache])
        #expect(board.recovery.calls.isEmpty)

        let recorded = try board.onlyRecordedFailure()
        #expect(recorded.severity == .error)
        #expect(recorded.additionalInfo?["failure_class"] == "unexpected")
        #expect(recorded.additionalInfo?["error_code"] == "9")
    }

    // MARK: - The board around the failure

    @Test
    func theLineClearsOnTheNextSuccessfulLoad() async {
        let board = Board(
            server: [
                .failure(Firestore.error(.unavailable)),
                .failure(Firestore.error(.unavailable)),
                .success([Self.stat("aaa")])
            ],
            deviceCopy: [Self.stat("aaa")]
        )

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)
        #expect(board.viewModel.errorMessage == Self.calmLine)

        // A retry in flight has not made the board current, so the line stays up until one
        // lands rather than blinking out and back.
        let viewModel = board.viewModel
        var lineWhileRefreshing: String?
        board.standings.beforeAnswering = { lineWhileRefreshing = viewModel.errorMessage }

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)
        #expect(lineWhileRefreshing == Self.calmLine)
        #expect(board.viewModel.errorMessage == nil)
        #expect(board.viewModel.refreshIssue == nil)
        #expect(board.viewModel.isOffline == false)
    }

    @Test
    func aFirstAnswerRecordsNothing() async {
        let board = Board(server: [.success([Self.stat("aaa")])])

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.errorMessage == nil)
        #expect(board.reporter.recordedErrors.isEmpty)
        #expect(board.analytics.records.isEmpty)
    }

    /// This session's last good load is newer than the copy on disk, so it is the one shown.
    @Test
    func theSessionsLastGoodBoardIsShownAheadOfTheCopyOnDisk() async {
        let board = Board(
            server: [.failure(Firestore.error(.unavailable)), .failure(Firestore.error(.unavailable))],
            deviceCopy: [Self.stat("disk")]
        )
        await board.cache.setDetailEntries([Self.stat("session")], for: .climb, timeFrame: .weekly)

        await board.viewModel.refreshLeaderboard(userId: "session", isNetworkConnected: true)

        #expect(board.viewModel.leaderboardEntries.map(\.userId) == ["session"])
        #expect(board.viewModel.errorMessage == Self.calmLine)
    }

    /// Written back, a stale copy would be served as fresh by the next ordinary load, which
    /// would then never ask the server again this session.
    @Test
    func aStaleBoardIsNotPromotedToTheSessionCache() async {
        let board = Board(
            server: [.failure(Firestore.error(.unavailable)), .failure(Firestore.error(.unavailable))],
            deviceCopy: [Self.stat("aaa")]
        )

        await board.viewModel.refreshLeaderboard(userId: "aaa", isNetworkConnected: true)

        #expect(board.viewModel.hasCachedEntries)
        #expect(await board.cache.detailEntries(for: .climb, timeFrame: .weekly) == nil)
    }

    // MARK: - Fixtures

    private static func stat(_ userId: String) -> FirestoreLeaderboardStats {
        let period = LeaderboardTimeFrame.weekly.currentPeriod()
        return FirestoreLeaderboardStats(
            userId: userId,
            displayName: "Climber \(userId)",
            photoURL: nil,
            timeFrame: LeaderboardTimeFrame.weekly.rawValue,
            schemaVersion: LeaderboardStats.currentSchemaVersion,
            periodKey: period.key,
            periodStartAt: period.startAt,
            totalSteps: 1_200,
            totalFloors: 75,
            totalWorkouts: 2,
            totalDuration: 1_800,
            stepsPerMinute: 40,
            lastUpdated: period.startAt
        )
    }

    /// A view model on a scripted standings read, with everything it reports captured.
    @MainActor
    private struct Board {
        let cache = LeaderboardSessionCache()
        let standings: ScriptedStandings
        let recovery: SpyAccessRecovery
        let reporter = RecordingCrashlyticsReporter()
        let analytics = InMemoryTelemetrySink(destination: .analytics)
        let viewModel: LeaderboardViewModel

        init(
            server: [Result<[FirestoreLeaderboardStats], any Error>],
            deviceCopy: [FirestoreLeaderboardStats] = [],
            recoveryHeals: Bool = true
        ) {
            standings = ScriptedStandings(server: server, deviceCopy: deviceCopy)
            recovery = SpyAccessRecovery(heals: recoveryHeals)
            viewModel = LeaderboardViewModel(
                sessionCache: cache,
                repository: standings,
                accessRecovery: recovery,
                telemetry: makeTestTelemetry(sink: analytics, reporter: reporter),
                failureContext: {
                    ServerReadFailureContext(
                        secondsSinceLaunch: 75,
                        secondsSinceForeground: 4,
                        networkInterface: .wifi
                    )
                },
                quietRetryDelay: .zero
            )
        }

        func onlyRecordedFailure() throws -> RecordingCrashlyticsReporter.RecordedError {
            #expect(reporter.recordedErrors.count == 1)
            return try #require(reporter.recordedErrors.first)
        }

        /// The event's own parameters, without the envelope every record carries.
        func onlyRefreshFailedEvent() throws -> [String: TelemetryValue] {
            #expect(analytics.records.count == 1)
            let record = try #require(analytics.records.first)
            #expect(record.name == "leaderboard_refresh_failed")
            return record.parameters.filter { TelemetryEnvelope.propertyKeys.contains($0.key) == false }
        }
    }
}

/// A standings read that fails the way the script says, and remembers which copy was asked for.
final class ScriptedStandings: LeaderboardStatsReading, @unchecked Sendable {
    private let lock = NSLock()
    private var server: [Result<[FirestoreLeaderboardStats], any Error>]
    private let deviceCopy: [FirestoreLeaderboardStats]
    private var recordedSources: [FirestoreSource] = []
    /// Runs on the main actor before each read answers, to sample what is on screen meanwhile.
    @MainActor var beforeAnswering: (() -> Void)?

    var sources: [FirestoreSource] {
        lock.withLock { recordedSources }
    }

    init(
        server: [Result<[FirestoreLeaderboardStats], any Error>],
        deviceCopy: [FirestoreLeaderboardStats] = []
    ) {
        self.server = server
        self.deviceCopy = deviceCopy
    }

    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        limit: Int,
        source: FirestoreSource
    ) async throws -> [FirestoreLeaderboardStats] {
        await MainActor.run { beforeAnswering?() }
        let result: Result<[FirestoreLeaderboardStats], any Error> = lock.withLock {
            recordedSources.append(source)
            if source == .cache { return .success(deviceCopy) }
            return server.isEmpty ? .failure(Firestore.error(.unavailable)) : server.removeFirst()
        }
        return try result.get()
    }
}

@MainActor
final class SpyAccessRecovery: RefusedAccessRecovering {
    private let heals: Bool
    /// One entry per reconciliation asked for, holding whether the climber initiated it.
    private(set) var calls: [Bool] = []

    init(heals: Bool = true) {
        self.heals = heals
    }

    func recoverRefusedAccess(userInitiated: Bool) async -> Bool {
        calls.append(userInitiated)
        return heals
    }
}
