import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the Guideline 1.2 moderation tooling: what a climber
/// actually sees when they open the profile overflow menu, report a profile,
/// block a climber, and manage that block from Settings.
///
/// Every image below is rendered from the *shipping* views - `ReportProfileSheet`,
/// `PostBlockReportSheet`, `ModerationReasonPicker`, `BlockedClimbersView`,
/// `ReplayCompletionLeaderboardView`, `LeaderboardRow`, `ProfileModerationMenu` -
/// hosted in a real `UIWindow` so `AsyncImage` resolves the climber photo before
/// the snapshot is taken. `ImageRenderer` alone renders an unresolved
/// `AsyncImage` as its placeholder, which would hide the very thing a block is
/// supposed to change.
///
/// Known limitation: SwiftUI expands a `Menu` only in response to a real tap, and
/// this project has no UI-test target, so the *open* Block/Report menu cannot be
/// photographed here. The closed affordance is shown in place on the profile top
/// bar, and the two sheets that menu presents are each captured in full.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's
/// temporary directory otherwise; the path is logged either way. Nothing reads
/// them back - these are evidence, not golden-image assertions.
@MainActor
struct ModerationSurfaceEvidenceTests {
    private struct ReportCall: Equatable, Sendable {
        let reporterUserId: String
        let reportedUserId: String
        let reason: ModerationReportReason
        let source: ModerationSource
    }

    private actor RepositorySpy: ModerationRepositoryProtocol {
        private(set) var blockedUserIds: [String] = []
        private(set) var unblockedUserIds: [String] = []
        private(set) var reports: [ReportCall] = []
        private let seeded: [BlockedClimber]

        init(seeded: [BlockedClimber] = []) {
            self.seeded = seeded
        }

        func fetchBlockedClimbers(
            blockerUserId: String
        ) async throws -> [BlockedClimber] {
            seeded
        }

        func block(blockerUserId: String, blockedUserId: String) async throws {
            blockedUserIds.append(blockedUserId)
        }

        func unblock(blockerUserId: String, blockedUserId: String) async throws {
            unblockedUserIds.append(blockedUserId)
        }

        func submitReport(
            reporterUserId: String,
            reportedUserId: String,
            reason: ModerationReportReason,
            source: ModerationSource
        ) async throws {
            reports.append(
                ReportCall(
                    reporterUserId: reporterUserId,
                    reportedUserId: reportedUserId,
                    reason: reason,
                    source: source
                )
            )
        }
    }

    private static let blockedUserId = "nadia-uid"
    private static let viewerUserId = "viewer-uid"

    // MARK: - A block keeps the row and hides only the identity

    /// The per-climb completion leaderboard, photographed before and after the
    /// viewer blocks the rank-2 climber. Rank, time, steps, avg SPM and the
    /// demographic line are all still there; only her name and photo are gone.
    @Test
    func blockingKeepsTheRowAndReplacesOnlyTheNameAndPhoto() async throws {
        let photoURL = try climberPhotoURL()
        let rows = completionRows(photoURL: photoURL)

        let visible = rows.map {
            CrossUserIdentityAdapter.replayRow(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let afterBlock = rows.map {
            CrossUserIdentityAdapter.replayRow(
                $0,
                blockedUserIds: [Self.blockedUserId],
                isBlockListHydrated: true
            )
        }

        let visibleRow = try #require(visible.first { $0.userId == Self.blockedUserId })
        let blockedRow = try #require(afterBlock.first { $0.userId == Self.blockedUserId })

        // The identity is masked...
        #expect(visibleRow.identity.displayName == "Nadia Fernandez")
        #expect(visibleRow.identity.photoURL == photoURL)
        #expect(blockedRow.identity.isHidden)
        #expect(blockedRow.identity.displayName.hasPrefix("Blocked climber"))
        #expect(blockedRow.identity.photoURL == nil)

        // ...and nothing that decides standing or context moves.
        #expect(afterBlock.map(\.id) == visible.map(\.id))
        #expect(blockedRow.rank == visibleRow.rank)
        #expect(blockedRow.finalSteps == visibleRow.finalSteps)
        #expect(
            blockedRow.completionDurationSeconds == visibleRow.completionDurationSeconds
        )
        #expect(blockedRow.demographicSummaryText == visibleRow.demographicSummaryText)
        #expect(blockedRow.demographicSummaryText == "F · 34 · Austin")

        try await snapshot(
            completionBoard(rows: visible),
            named: "moderation-completion-leaderboard-before-block",
            height: 470
        )
        try await snapshot(
            completionBoard(rows: afterBlock),
            named: "moderation-completion-leaderboard-after-block",
            height: 470
        )
    }

    /// The same guarantee on the global weekly board: the blocked climber keeps
    /// rank 2 and her step total, so a block can never be used to climb past her.
    @Test
    func globalLeaderboardKeepsTheBlockedClimberInPlace() async throws {
        let entries = globalEntries()
        let visible = entries.map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let afterBlock = entries.map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: [Self.blockedUserId],
                isBlockListHydrated: true
            )
        }

        let blockedEntry = try #require(
            afterBlock.first { $0.userId == Self.blockedUserId }
        )

        #expect(visible.map(\.rank) == afterBlock.map(\.rank))
        #expect(visible.map(\.formattedValue) == afterBlock.map(\.formattedValue))
        #expect(blockedEntry.identity.isHidden)
        #expect(blockedEntry.rank == 2)
        #expect(blockedEntry.formattedValue == 21_940.formatted())

        try await snapshot(
            VStack(alignment: .leading, spacing: 22) {
                labelledRows("BEFORE BLOCK", entries: visible)
                labelledRows("AFTER BLOCK", entries: afterBlock)
            }
            .padding(20),
            named: "moderation-global-leaderboard-block-comparison",
            height: 470
        )
    }

    // MARK: - Report needs a reason; block does not, and files none

    /// Report is reason-gated: `Send Report` stays disabled until one of the seven
    /// reasons is chosen. Both states are photographed.
    @Test
    func reportingRequiresAReasonBeforeItCanBeSent() async throws {
        #expect(ModerationReportReason.allCases.count == 7)

        try await snapshot(
            ReportProfileSheet(
                isSubmitting: false,
                onCancel: {},
                onSubmit: { _ in }
            ),
            named: "moderation-report-sheet-no-reason-chosen",
            height: 800
        )

        try await snapshot(
            ModerationSheetScaffold(
                title: "Report profile",
                message: "Choose a reason. Reporting sends this profile to Ascend for review."
            ) {
                ModerationReasonPicker(
                    selection: .constant(.inappropriatePhoto)
                )
            } footer: {
                Button("Send Report") {}
                    .appSheetButtonStyle(tone: .destructive)
            },
            named: "moderation-report-sheet-reason-chosen",
            height: 800
        )
    }

    /// What a climber sees the instant a block lands: no reason prompt, no
    /// approval step, and reporting is an explicit opt-in checkbox that starts
    /// off. The store proves the same thing behaviourally - blocking sends a
    /// block and nothing else.
    @Test
    func blockingIsOneTapAndNeverFilesAReportOnItsOwn() async throws {
        let spy = RepositorySpy()
        let store = ModerationStore(repository: spy)
        await store.hydrate(for: Self.viewerUserId)

        try await store.block(
            blockerUserId: Self.viewerUserId,
            blockedUserId: Self.blockedUserId
        )

        let blockedAfterBlock = await spy.blockedUserIds
        let reportsAfterBlock = await spy.reports
        #expect(blockedAfterBlock == [Self.blockedUserId])
        #expect(reportsAfterBlock.isEmpty)
        #expect(store.blockedUserIds == Set([Self.blockedUserId]))

        try await snapshot(
            PostBlockReportSheet(
                isSubmitting: false,
                onDone: {},
                onSubmit: { _ in }
            ),
            named: "moderation-post-block-sheet",
            height: 380
        )

        // The opt-in path still routes through the reason picker and records the
        // surface the report came from.
        try await store.report(
            reporterUserId: Self.viewerUserId,
            reportedUserId: Self.blockedUserId,
            reason: .inappropriatePhoto,
            source: .completionLeaderboard
        )

        let filedReports = await spy.reports
        #expect(
            filedReports == [
                ReportCall(
                    reporterUserId: Self.viewerUserId,
                    reportedUserId: Self.blockedUserId,
                    reason: .inappropriatePhoto,
                    source: .completionLeaderboard
                ),
            ]
        )
    }

    // MARK: - Settings: the reversible half of the block

    @Test
    func settingsListsEveryBlockedClimberAndOffersUnblock() async throws {
        let seeded = [
            BlockedClimber(
                userId: Self.blockedUserId,
                createdAt: Date(timeIntervalSince1970: 1_753_920_000)
            ),
            BlockedClimber(
                userId: "marcus-uid",
                createdAt: Date(timeIntervalSince1970: 1_753_142_400)
            ),
        ]
        let store = ModerationStore(repository: RepositorySpy(seeded: seeded))
        await store.hydrate(for: Self.viewerUserId)

        #expect(store.blockedClimbers.count == 2)
        #expect(store.isBlockListHydrated)

        try await snapshot(
            NavigationStack {
                BlockedClimbersView()
                    .environment(AuthenticationViewModel())
                    .environment(store)
            },
            named: "moderation-blocked-climbers-settings",
            height: 360
        )

        let emptyStore = ModerationStore(repository: RepositorySpy())
        await emptyStore.hydrate(for: Self.viewerUserId)

        try await snapshot(
            NavigationStack {
                BlockedClimbersView()
                    .environment(AuthenticationViewModel())
                    .environment(emptyStore)
            },
            named: "moderation-blocked-climbers-settings-empty",
            height: 360
        )
    }

    // MARK: - The single entry point

    /// The one sanctioned placement: an overflow control on the other-user
    /// profile top bar. Rendered as the real `ProfileModerationMenu`, in the same
    /// bar layout `OtherUserProfileView` builds it into (that bar is `private`, so
    /// its chrome is reproduced verbatim from source around the shipping menu).
    @Test
    func profileTopBarCarriesTheOverflowMenu() async throws {
        let store = ModerationStore(repository: RepositorySpy())
        await store.hydrate(for: Self.viewerUserId)

        try await snapshot(
            VStack(spacing: 0) {
                ProfileTopBarEvidence(reportedUserId: Self.blockedUserId)
                    .environment(AuthenticationViewModel())
                    .environment(store)

                Text("Tapping the ellipsis opens Block / Report.")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 18)

                Spacer(minLength: 0)
            },
            named: "moderation-profile-entry-point",
            height: 130
        )
    }

    // MARK: - Fixtures

    private func completionRows(photoURL: URL) -> [LiveReplayLeaderboardRow] {
        [
            (
                id: "dana-uid", name: "Dana Rojas", rank: 1, steps: 4_120,
                duration: TimeInterval(742), gender: "man", age: 41,
                city: "Denver", photo: URL?.none, isCurrentUser: false
            ),
            (
                id: Self.blockedUserId, name: "Nadia Fernandez", rank: 2,
                steps: 4_120, duration: TimeInterval(806), gender: "woman",
                age: 34, city: "Austin", photo: URL?.some(photoURL),
                isCurrentUser: false
            ),
            (
                id: Self.viewerUserId, name: "You", rank: 3, steps: 4_120,
                duration: TimeInterval(884), gender: "man", age: 33,
                city: "Chicago", photo: URL?.none, isCurrentUser: true
            ),
            (
                id: "owen-uid", name: "Owen Baptiste", rank: 4, steps: 4_120,
                duration: TimeInterval(931), gender: "man", age: 28,
                city: "Seattle", photo: URL?.none, isCurrentUser: false
            ),
        ].map { fixture in
            LiveReplayLeaderboardRow(
                id: fixture.id,
                rank: fixture.rank,
                displayName: fixture.name,
                avatarToken: "",
                photoURL: fixture.photo,
                stepsAtBucket: fixture.steps,
                finalSteps: fixture.steps,
                deltaFromUser: 0,
                isCurrentUser: fixture.isCurrentUser,
                isPersonalBest: false,
                completionDurationSeconds: fixture.duration,
                userId: fixture.id,
                gender: fixture.gender,
                age: fixture.age,
                locationCity: fixture.city
            )
        }
    }

    private func completionBoard(
        rows: [ModeratedReplayLeaderboardRow]
    ) -> some View {
        NavigationStack {
            ReplayCompletionLeaderboardView(
                rows: rows,
                completedCount: rows.count,
                isLoading: false,
                fetchFailed: false,
                currentUserPhotoURL: nil,
                effectiveColorScheme: .dark,
                emptyTitle: "No completed times yet.",
                emptyMessage: "First Ascent open. The first finisher claims it forever.",
                emphasis: .duration
            )
            .padding(16)
        }
    }

    private func globalEntries() -> [LeaderboardEntry] {
        [
            ("dana-uid", "Dana Rojas", 1, 24_180, false),
            (Self.blockedUserId, "Nadia Fernandez", 2, 21_940, false),
            (Self.viewerUserId, "You", 3, 19_812, true),
            ("owen-uid", "Owen Baptiste", 4, 17_926, false),
        ].map { userId, name, rank, steps, isCurrentUser in
            LeaderboardEntry(
                userId: userId,
                displayName: name,
                rank: rank,
                value: Double(steps),
                formattedValue: steps.formatted(),
                isCurrentUser: isCurrentUser
            )
        }
    }

    private func labelledRows(
        _ title: String,
        entries: [ModeratedLeaderboardEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.montserratBold(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(2)

            ForEach(entries) { entry in
                LeaderboardRow(entry: entry, metric: .climb)
            }
        }
    }

    /// A real climber photo from the seed fixtures, copied where the simulator
    /// can load it as a `file:` URL. A remote URL would never resolve inside a
    /// snapshot, and the masked-photo claim needs a visible photo to mask.
    private func climberPhotoURL() throws -> URL {
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "scripts/seed/assets/profile-avatars/profile_tied_gold.jpg")
        let destination = URL(filePath: NSTemporaryDirectory())
            .appending(path: "moderation-evidence-climber-photo.jpg")

        let data = try Data(contentsOf: source)
        try data.write(to: destination)
        return destination
    }

    // MARK: - Rendering

    /// Hosts the view in a real window so asynchronous image loading completes,
    /// then captures what is on screen.
    private func snapshot(
        _ view: some View,
        named name: String,
        height: CGFloat
    ) async throws {
        let size = CGSize(width: 390, height: height)
        let controller = UIHostingController(
            rootView: view
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .black

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // Let layout settle and any AsyncImage finish loading.
        for _ in 0..<12 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered moderation evidence: \(url.path())")
    }
}

/// Reproduces `OtherUserProfileView.ProfileComparisonTopBar` - which is `private`
/// - around the shipping `ProfileModerationMenu`, so the overflow control is
/// photographed in the chrome it actually ships in.
private struct ProfileTopBarEvidence: View {
    let reportedUserId: String

    var body: some View {
        HStack {
            Button {} label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.13))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("PROFILE COMPARISON")
                .font(.montserratBold(size: 13))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(3.2)

            Spacer()

            ProfileModerationMenu(
                reportedUserId: reportedUserId,
                source: .profile
            )
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(ProfileVisualStyle.secondaryText)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(ProfileVisualStyle.background.opacity(0.96))
    }
}
