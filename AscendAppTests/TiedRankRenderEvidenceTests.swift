import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Renders the leaderboard surfaces a climber actually sees when two of them tie, and
/// writes the images out for review. Assertions cover the labels; the images cover the
/// part CLAUDE.md asks a human to judge — that a shared rank is *visually obvious*.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set, and in the test host's temporary
/// directory otherwise; either way the path is logged. Nothing here reads them back, so
/// these are evidence rather than golden-image assertions — no snapshot to re-record when
/// an unrelated colour or font changes.
@MainActor
struct TiedRankRenderEvidenceTests {
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

    /// A per-climb field where two climbers finished on the same second: 10:00, 11:40,
    /// 11:40, 13:20. Competition ranking makes that 1, 2, 2, 4.
    private static let tiedDurations: [TimeInterval] = [600, 700, 700, 800]

    // MARK: - Per-climb completion leaderboard

    @Test
    func perClimbBoardShowsOneSharedRankForTheTiedClimbers() async throws {
        let board = makeCompletionBoard(ranks: competitionRanks())
        let moderationStore = await hydratedModerationStore()

        // The ranks the repository now assigns, and the tie flags the board derives.
        #expect(board.rows.map(\.rank) == [1, 2, 2, 4])
        #expect(board.rows.map(\.isTied) == [false, true, true, false])

        try render(
            completionBoard(board)
                .environment(moderationStore),
            named: "per-climb-leaderboard-after",
            height: 420
        )
    }

    /// The same field as the old client rendered it: `startRank + offset`, no tie flag.
    /// `rankLabel(3, isTied: false, untiedPrefix: "#")` is "#3" — byte-identical to the
    /// `Text("#\(rank)")` this replaced — so the image reproduces the reported screen.
    @Test
    func perClimbBoardBeforeNumberedTiedClimbersByPosition() async throws {
        let board = makeCompletionBoard(ranks: positionalRanks())
        let moderationStore = await hydratedModerationStore()

        #expect(board.rows.map(\.rank) == [1, 2, 3, 4])
        #expect(board.rows.allSatisfy { $0.isTied == false })

        try render(
            completionBoard(board)
                .environment(moderationStore),
            named: "per-climb-leaderboard-before",
            height: 420
        )
    }

    /// The contradiction the report describes, on one screen: the pinned row counted
    /// strictly-faster completions while the list numbered by position.
    @Test
    func pinnedRankAndListRankNowAgreeForTheTiedClimber() {
        let tiedIndex = 2
        let duration = Self.tiedDurations[tiedIndex]

        // What the pinned row shows — countRowsFasterThan + 1, matching the server.
        let pinnedRank = Self.tiedDurations.count(where: { $0 < duration }) + 1

        #expect(positionalRanks()[tiedIndex] == 3)
        #expect(pinnedRank == 2)
        #expect(competitionRanks()[tiedIndex] == pinnedRank)
    }

    // MARK: - Global leaderboard tab

    @Test
    func podiumSeatsBothClimbersTiedForGoldAndLabelsThemT1() async throws {
        // Dana and Priya finished the week on the same step total.
        let entries = makeGlobalEntries(
            ranks: [1, 1, 3, 4],
            steps: [21_482, 21_482, 19_812, 17_926]
        )
        let moderationStore = await hydratedModerationStore()
        let moderatedEntries = entries.map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let layout = ModeratedLeaderboardPodiumLayout(entries: moderatedEntries)

        // Keying pedestals by rank dropped one of the two golds outright.
        #expect(layout.slots.compactMap { $0.entry?.userId }.count == 3)
        #expect(layout.slots.filter { $0.displayedRank == 1 }.count == 2)
        #expect(CompetitionRanking.rankLabel(1, isTied: true) == "T1")

        try render(
            LeaderboardPodiumView(
                entries: ModeratedLeaderboardPodiumLayout.podiumEntries(
                    from: moderatedEntries
                ),
                metric: .climb
            )
            .environment(moderationStore)
            .padding(16),
            named: "global-podium-tied-for-gold-after",
            height: 260
        )
    }

    @Test
    func globalListAndPinnedRowShowTheSameTiedRank() async throws {
        let entries = makeGlobalEntries(
            ranks: [1, 2, 2, 4],
            steps: [21_482, 19_812, 19_812, 17_926]
        )
        let you = try #require(entries.last { $0.isCurrentUser })
        let moderationStore = await hydratedModerationStore()

        #expect(you.rank == 2)
        #expect(you.isTied)

        try render(
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in
                    LeaderboardRow(
                        entry: CrossUserIdentityAdapter.leaderboardEntry(
                            entry,
                            blockedUserIds: [],
                            isBlockListHydrated: true
                        ),
                        metric: .climb
                    )
                }

                Divider().overlay(Color.white.opacity(0.2))

                LeaderboardUserRowView(
                    entry: CrossUserIdentityAdapter.leaderboardEntry(
                        you,
                        blockedUserIds: [],
                        isBlockListHydrated: true
                    ),
                    metric: .climb,
                    crownGapText: nil
                )
            }
            .environment(moderationStore)
            .padding(16),
            named: "global-list-and-pinned-row-after",
            height: 320
        )
    }

    /// The old global board numbered by list position, so two climbers on identical step
    /// totals read 2 and 3 — while the Cloud Function had already awarded both of them
    /// rank 2 when it decided achievements.
    @Test
    func globalBoardBeforeSplitEqualStepTotalsAcrossTwoRanks() async throws {
        // The same week as `globalListAndPinnedRowShowTheSameTiedRank`, ranked the old way.
        let entries = makeGlobalEntries(
            ranks: [1, 2, 3, 4],
            steps: [21_482, 19_812, 19_812, 17_926],
            marksTies: false
        )
        let you = try #require(entries.last { $0.isCurrentUser })
        let moderationStore = await hydratedModerationStore()

        #expect(you.rank == 3)
        #expect(CompetitionRanking.ranks(for: entries, key: \.value)[2] == 2)

        try render(
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in
                    LeaderboardRow(
                        entry: CrossUserIdentityAdapter.leaderboardEntry(
                            entry,
                            blockedUserIds: [],
                            isBlockListHydrated: true
                        ),
                        metric: .climb
                    )
                }

                Divider().overlay(Color.white.opacity(0.2))

                LeaderboardUserRowView(
                    entry: CrossUserIdentityAdapter.leaderboardEntry(
                        you,
                        blockedUserIds: [],
                        isBlockListHydrated: true
                    ),
                    metric: .climb,
                    crownGapText: nil
                )
            }
            .environment(moderationStore)
            .padding(16),
            named: "global-list-and-pinned-row-before",
            height: 320
        )
    }

    // MARK: - Unranked climber

    /// The photographed contradiction, on one screen: one climber on the podium with
    /// places 2 and 3 unclaimed, and the pinned YOU row beneath claiming rank 2 on 0
    /// steps — a rank borrowed from list position.
    @Test
    func sparsePodiumAndPinnedRowBeforeGaveTheZeroActivityClimberRankTwo() async throws {
        let entries = makeGlobalEntries(ranks: [1], steps: [48_000], currentUserIndex: nil)
        let moderated = moderatedEntries(entries)
        let moderationStore = await hydratedModerationStore()

        // What `placeholderEntry` produced: leaderboardEntries.count + 1.
        let positionalRank = moderated.count + 1
        #expect(positionalRank == 2)

        let placeholder = LeaderboardEntry(
            userId: "you",
            displayName: "You",
            rank: positionalRank,
            value: 0,
            formattedValue: "0",
            isCurrentUser: true,
            isTied: false
        )

        try render(
            VStack(alignment: .leading, spacing: 12) {
                LeaderboardPodiumView(
                    entries: ModeratedLeaderboardPodiumLayout.podiumEntries(from: moderated),
                    metric: .climb
                )

                LeaderboardUserRowView(
                    entry: CrossUserIdentityAdapter.leaderboardEntry(
                        placeholder,
                        blockedUserIds: [],
                        isBlockListHydrated: true
                    ),
                    metric: .climb,
                    crownGapText: "48,000 STEPS TO CROWN"
                )
            }
            .environment(moderationStore)
            .padding(16),
            named: "global-unranked-pinned-row-before",
            height: 400
        )
    }

    /// The same board after: the second and third plinths stay unclaimed and the pinned
    /// row shows no rank at all, so the two surfaces state the same thing.
    @Test
    func sparsePodiumAndUnrankedRowNowAgreeThatNoOneHoldsSecond() async throws {
        let entries = makeGlobalEntries(ranks: [1], steps: [48_000], currentUserIndex: nil)
        let moderated = moderatedEntries(entries)
        let podiumEntries = ModeratedLeaderboardPodiumLayout.podiumEntries(from: moderated)
        let moderationStore = await hydratedModerationStore()

        // Only the leader is ranked; no entry claims second or third.
        #expect(podiumEntries.map(\.rank) == [1])
        #expect(LeaderboardUserRowView.unrankedRankLabel == "-")

        try render(
            VStack(alignment: .leading, spacing: 12) {
                LeaderboardPodiumView(entries: podiumEntries, metric: .climb)

                LeaderboardUserRowView(
                    unrankedFormattedValue: "0",
                    photoURL: nil,
                    metric: .climb,
                    crownGapText: "48,000 STEPS TO CROWN"
                )
            }
            .environment(moderationStore)
            .padding(16),
            named: "global-unranked-pinned-row-after",
            height: 400
        )
    }

    // MARK: - Fixtures

    private func competitionRanks() -> [Int] {
        CompetitionRanking.ranks(for: Self.tiedDurations) { $0 }
    }

    /// What the client did before: rank by list position.
    private func positionalRanks() -> [Int] {
        Self.tiedDurations.indices.map { $0 + 1 }
    }

    private func makeCompletionBoard(ranks: [Int]) -> LiveReplayCompletionLeaderboard {
        let names = ["Dana R.", "Priya S.", "Marcus T.", "Owen B."]
        let rows = zip(zip(Self.tiedDurations, ranks).map { $0 }, names.indices).map {
            pair, index -> LiveReplayLeaderboardRow in
            let (duration, rank) = pair
            return LiveReplayLeaderboardRow(
                id: "row-\(index)",
                rank: rank,
                displayName: names[index],
                avatarToken: String(names[index].prefix(1)),
                photoURL: nil,
                stepsAtBucket: 4_000,
                finalSteps: 4_000,
                deltaFromUser: 0,
                isCurrentUser: index == 2,
                isPersonalBest: false,
                completionDurationSeconds: duration,
                userId: "user-\(index)"
            )
        }

        return LiveReplayCompletionLeaderboard(
            rows: rows,
            completedCount: rows.count,
            updatedAt: nil
        )
    }

    private func completionBoard(_ board: LiveReplayCompletionLeaderboard) -> some View {
        ReplayCompletionLeaderboardView(
            rows: board.rows.map {
                CrossUserIdentityAdapter.replayRow(
                    $0,
                    blockedUserIds: [],
                    isBlockListHydrated: true
                )
            },
            completedCount: board.completedCount,
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

    private func hydratedModerationStore() async -> ModerationStore {
        let store = ModerationStore(repository: EmptyModerationRepository())
        await store.hydrate(for: "render-evidence-user")
        return store
    }

    /// A climber is tied when another climber shares their *step total* — the ranking
    /// value — not merely their rank number. That keeps the rendered board in a state
    /// the app can actually reach.
    /// - Parameter marksTies: `false` reproduces the old client, which had no tie
    ///   concept at all.
    /// - Parameter currentUserIndex: `nil` renders a field the signed-in climber is not
    ///   in at all, which is what an unranked climber sees.
    private func makeGlobalEntries(
        ranks: [Int],
        steps: [Int],
        marksTies: Bool = true,
        currentUserIndex: Int? = 2
    ) -> [LeaderboardEntry] {
        let names = ["Dana R.", "Priya S.", "Marcus T.", "Owen B."]

        return ranks.indices.map { index in
            LeaderboardEntry(
                userId: "user-\(index)",
                displayName: names[index],
                rank: ranks[index],
                value: Double(steps[index]),
                formattedValue: steps[index].formatted(),
                isCurrentUser: index == currentUserIndex,
                isTied: marksTies && steps.count(where: { $0 == steps[index] }) > 1
            )
        }
    }

    private func moderatedEntries(
        _ entries: [LeaderboardEntry]
    ) -> [ModeratedLeaderboardEntry] {
        entries.map {
            CrossUserIdentityAdapter.leaderboardEntry(
                $0,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
    }

    // MARK: - Rendering

    private func render(_ view: some View, named name: String, height: CGFloat) throws {
        let renderer = ImageRenderer(
            content: view
                .frame(width: 390)
                .frame(height: height, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        // Logged so the image is findable inside the simulator container when no
        // ASCEND_EVIDENCE_DIR was provided.
        print("Rendered tied-rank evidence: \(url.path())")
    }
}
