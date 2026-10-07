import FirebaseFirestore
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The shipping Leaderboards tab in each state a failed refresh can leave it in.
///
/// The captain saw `Showing cached data. Latest refresh failed.` twice after a production
/// release. Once it was a real outage (rules refused the read, 2026-09-25) and once nothing was
/// wrong (the phone's Firestore stream dropped for five minutes, 2026-10-03), and the board said
/// the same thing both times. These host the real `LeaderboardView` on a real
/// `LeaderboardViewModel` whose standings read fails the way Firestore does, and prove from the
/// accessibility tree what each cause now puts on screen.
///
/// Photographs are written only when `ASCEND_EVIDENCE_DIR` is set. Nothing reads them back.
@MainActor
@Suite(.hostsAWindow)
struct LeaderboardRefreshFailureEvidenceTests {
    private static let calmLine = "leaderboard not updated. pull to retry."
    private static let accessLine = "ascend couldn't confirm your access. pull to retry."

    /// 2026-10-03, had the stream stayed down: asked, asked once more two seconds later, then
    /// the last board with one calm line and the next step.
    @Test
    func aStreamThatStaysDownLeavesTheLastBoardUnderOneCalmLine() async throws {
        let viewModel = makeViewModel(
            server: [.failure(Firestore.error(.unavailable)), .failure(Firestore.error(.unavailable))],
            deviceCopy: Self.board
        )
        await viewModel.refreshLeaderboard(userId: Self.viewerId, isNetworkConnected: true)

        try await hostAndPhotograph(viewModel, named: "leaderboard-refresh-unreachable") { copy in
            #expect(copy.contains(Self.calmLine), "The calm line is not on screen: \(copy)")
            #expect(copy.contains(Self.accessLine) == false)
        }
    }

    /// 2026-10-03 as it actually went: the stream was back within seconds. The quiet retry
    /// absorbs it and the climber is told nothing, because nothing is wrong.
    @Test
    func aStreamThatComesBackOnTheQuietRetryShowsNoLineAtAll() async throws {
        let viewModel = makeViewModel(
            server: [.failure(Firestore.error(.unavailable)), .success(Self.board)]
        )
        await viewModel.refreshLeaderboard(userId: Self.viewerId, isNetworkConnected: true)

        try await hostAndPhotograph(viewModel, named: "leaderboard-refresh-recovered") { copy in
            #expect(copy.contains("pull to retry") == false, "A recovered refresh still shows a line: \(copy)")
            #expect(copy.contains("not updated") == false)
        }
    }

    /// 2026-09-25: the server refused. Reconciliation is asked once; when the refusal stands,
    /// the line names access rather than the connection.
    @Test
    func aRefusalThatSurvivesReconciliationNamesAccess() async throws {
        let recovery = SpyAccessRecovery()
        let viewModel = makeViewModel(
            server: [
                .failure(Firestore.error(.permissionDenied)),
                .failure(Firestore.error(.permissionDenied))
            ],
            deviceCopy: Self.board,
            recovery: recovery
        )
        await viewModel.refreshLeaderboard(userId: Self.viewerId, isNetworkConnected: true)
        #expect(recovery.calls.count == 1)

        try await hostAndPhotograph(viewModel, named: "leaderboard-refresh-refused") { copy in
            #expect(copy.contains(Self.accessLine), "The access line is not on screen: \(copy)")
            #expect(copy.contains(Self.calmLine) == false)
        }
    }

    /// The same refusal on a phone holding no copy of the board at all.
    @Test
    func aRefusalWithNoBoardToShowStallsWithTheAccessLine() async throws {
        let viewModel = makeViewModel(server: [
            .failure(Firestore.error(.permissionDenied)),
            .failure(Firestore.error(.permissionDenied))
        ])
        await viewModel.refreshLeaderboard(userId: Self.viewerId, isNetworkConnected: true)

        try await hostAndPhotograph(viewModel, named: "leaderboard-refresh-refused-empty") { copy in
            #expect(copy.contains("leaderboard stalled."), "The stalled state is not on screen: \(copy)")
            #expect(copy.contains(Self.accessLine))
        }
    }

    // MARK: - The board

    private static let viewerId = "refresh-evidence-viewer"

    private static let board: [FirestoreLeaderboardStats] = [
        stat("refresh-evidence-1", name: "Maya Chen", steps: 48_210),
        stat("refresh-evidence-2", name: "Jonas Weber", steps: 41_876),
        stat("refresh-evidence-3", name: "Priya Nair", steps: 37_402),
        stat(viewerId, name: "Sam Ortiz", steps: 29_115),
        stat("refresh-evidence-5", name: "Lena Fischer", steps: 21_660)
    ]

    private static func stat(_ userId: String, name: String, steps: Int) -> FirestoreLeaderboardStats {
        let period = LeaderboardTimeFrame.weekly.currentPeriod()
        return FirestoreLeaderboardStats(
            userId: userId,
            displayName: name,
            photoURL: nil,
            timeFrame: LeaderboardTimeFrame.weekly.rawValue,
            schemaVersion: LeaderboardStats.currentSchemaVersion,
            periodKey: period.key,
            periodStartAt: period.startAt,
            totalSteps: steps,
            totalFloors: steps / 16,
            totalWorkouts: 4,
            totalDuration: 7_200,
            stepsPerMinute: 62,
            lastUpdated: period.startAt
        )
    }

    private func makeViewModel(
        server: [Result<[FirestoreLeaderboardStats], any Error>],
        deviceCopy: [FirestoreLeaderboardStats] = [],
        recovery: SpyAccessRecovery = SpyAccessRecovery()
    ) -> LeaderboardViewModel {
        LeaderboardViewModel(
            sessionCache: LeaderboardSessionCache(),
            repository: ScriptedStandings(server: server, deviceCopy: deviceCopy),
            accessRecovery: recovery,
            telemetry: makeTestTelemetry(sinks: []),
            quietRetryDelay: .zero
        )
    }

    // MARK: - The board on screen

    private actor EmptyModerationRepository: ModerationRepositoryProtocol {
        func fetchBlockedClimbers(
            blockerUserId: String,
            source: BlockListReadSource
        ) async throws -> [BlockedClimber] {
            []
        }

        func block(blockerUserId: String, blockedUserId: String) async throws {}

        func unblock(blockerUserId: String, blockedUserId: String) async throws {}

        func submitReport(
            reporterUserId: String,
            reportedUserId: String,
            reason: ModerationReportReason,
            source: ModerationSource
        ) async throws {}
    }

    /// Hosts the shipping board on `viewModel` in a real window, hands the on-screen copy to
    /// `verify`, and photographs it when this run keeps photographs.
    ///
    /// The host is signed out whatever session the simulator's keychain holds, so the view's own
    /// `setupAndLoad` returns before it loads anything and the state on screen is exactly the one
    /// the refresh above left the view model in.
    private func hostAndPhotograph(
        _ viewModel: LeaderboardViewModel,
        named name: String,
        verify: (String) -> Void
    ) async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self
        )
        let moderationStore = ModerationStore(repository: EmptyModerationRepository())
        await moderationStore.hydrate(for: Self.viewerId)

        let size = CGSize(width: 390, height: 780)
        try await RenderedScreen.host(
            NavigationStack {
                LeaderboardView(initialTimeFrame: .weekly, viewSource: .tab, viewModel: viewModel)
            }
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .environment(moderationStore)
            .environment(NetworkConnectivityService.shared)
            .environment(TabRouter())
            .modelContainer(container)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            // The view holds the closing command together with non-breaking spaces, so that a
            // wrap falls between the two sentences; the lines are compared as plain text.
            let copy = try await screen.copy().replacing("\u{00A0}", with: " ")
            verify(copy)
            // The storage vocabulary the old banner used never reaches a climber again.
            #expect(copy.contains("cached") == false, "The board still says cached: \(copy)")
            try screen.photograph(named: name)
        }
    }
}
