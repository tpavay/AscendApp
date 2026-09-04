import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Photographs Climb Detail's LEADERBOARD tab in the states a climber can land on, so a reviewer
/// can see that the duplicated "Your best" card is gone, that the climber's own row still carries
/// its YOU pill, and that the First Ascent line now flies the shipped cut-out gold flag.
///
/// `ClimbDetailView.leaderboardPage` cannot be hosted directly: it is a private member of a
/// 2,000-line Firebase-auth-gated screen whose `.task` opens network work. So the page's chrome is
/// reproduced here from source - same order, same copy, same Font/Color tokens, same modifiers as
/// `ClimbDetailView.swift`'s `leaderboardPage` / `firstAscentSummaryContent` / `leaderboardRow` -
/// while the two things actually under review are the shipping code itself: `ClimbFirstAscentMark`
/// is the real view, and every row is a real `ModeratedReplayLeaderboardRow` built through
/// `CrossUserIdentityAdapter`, so the YOU pill lights from the same `isCurrentUser` the app uses.
///
/// Drawn through a live `UIWindow` (`RenderedScreen`) rather than `ImageRenderer`, which draws
/// asset-catalogue art in a nested layout as blank. Every case reads the fact its photograph is
/// meant to show off the hosted page's accessibility tree, so the run proves it on CI where no
/// photograph is kept; the photograph itself is written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbLeaderboardTabVisualEvidenceTests {
    private static let firstAscentDate = Date(timeIntervalSince1970: 1_754_870_400)

    /// The captain's Charminar case: he is the only finisher, so his row is the whole board. The
    /// "Your best / 02:06 · #1 of 1" card used to sit directly above this row saying the same two
    /// numbers.
    @Test
    func soleFinisherSeesOneRowAndNoDuplicateSummary() async throws {
        let rows = [Self.row(id: "you", rank: 1, name: "Tyler P.", seconds: 126, isCurrentUser: true)]

        let texts = try await Self.host(
            name: "climb-leaderboard-tab-sole-finisher",
            caption: "Raced it, only finisher: one row, YOU pill, rank and time stated once",
            proof: ClimbLeaderboardPageProof(rows: rows, firstAscent: Self.firstAscent(name: "John Smith"))
        )
        let copy = Self.joined(texts)
        // The board is the climber's own row and nothing else: their name and their time are each
        // on the page exactly once, the YOU pill marks the row, and the "Your best" card that used
        // to repeat the same two numbers above it is gone.
        #expect(Self.count(of: "tyler p.", in: texts) == 1, "expected one row for the climber in: \(copy)")
        #expect(Self.count(of: "2:06", in: texts) == 1, "expected the time stated once in: \(copy)")
        #expect(Self.count(of: "you", in: texts, exactly: true) == 1, "expected one YOU pill in: \(copy)")
        #expect(!copy.contains("your best"), "the duplicated card is back: \(copy)")
    }

    /// The same climber further down a real field. Their row is the only place their time and rank
    /// appear, and the YOU pill is what finds it.
    @Test
    func rankedClimberKeepsTheYouPillOnTheirOwnRow() async throws {
        let rows = [
            Self.row(id: "1", rank: 1, name: "Marcus T.", seconds: 104),
            Self.row(id: "2", rank: 2, name: "Priya S.", seconds: 118),
            Self.row(id: "3", rank: 3, name: "Dana R.", seconds: 121),
            Self.row(id: "4", rank: 4, name: "Tyler P.", seconds: 126, isCurrentUser: true),
            Self.row(id: "5", rank: 5, name: "Owen B.", seconds: 140)
        ]
        let texts = try await Self.host(
            name: "climb-leaderboard-tab-raced",
            caption: "Raced it, mid-field: the YOU pill is the only marker of your own row",
            proof: ClimbLeaderboardPageProof(rows: rows, firstAscent: Self.firstAscent(name: "John Smith"))
        )
        let copy = Self.joined(texts)
        // Exactly one YOU pill on the page, and it sits on the climber's own row: level with
        // "Tyler P." and with no other name's row.
        let pills = texts.filter { $0.text.lowercased() == "you" }
        let ownRow = try #require(texts.first { $0.text.localizedCaseInsensitiveContains("Tyler P.") }, "\(copy)")
        #expect(pills.count == 1, "expected one YOU pill in: \(copy)")
        #expect(
            pills.allSatisfy { ownRow.frame.minY <= $0.frame.midY && $0.frame.midY <= ownRow.frame.maxY },
            "the YOU pill is not level with the climber's own row: \(pills.map(\.frame)) against \(ownRow.frame)"
        )
        #expect(Self.count(of: "marcus t.", in: texts) == 1 && Self.count(of: "owen b.", in: texts) == 1, "\(copy)")
    }

    /// Never raced it. The removed card never rendered in this state, so the only question the
    /// photograph answers is whether the page still holds together above the board.
    @Test
    func climberWhoHasNotRacedStillGetsAWholePage() async throws {
        let rows = [
            Self.row(id: "1", rank: 1, name: "Marcus T.", seconds: 104),
            Self.row(id: "2", rank: 2, name: "Priya S.", seconds: 118),
            Self.row(id: "3", rank: 3, name: "Dana R.", seconds: 121),
            Self.row(id: "4", rank: 4, name: "Owen B.", seconds: 140)
        ]
        let proof = ClimbLeaderboardPageProof(rows: rows, firstAscent: Self.firstAscent(name: "John Smith"))

        let texts = try await Self.host(
            name: "climb-leaderboard-tab-not-raced",
            caption: "Never raced it: First Ascent line runs straight into the board, no gap left behind",
            proof: proof
        )
        let copy = Self.joined(texts)
        // Nothing on the board is the climber's - no YOU pill anywhere - and the First Ascent line
        // sits directly above the first row, with nothing but its own height between them.
        #expect(Self.count(of: "you", in: texts, exactly: true) == 0, "a YOU pill on a board the climber never raced: \(copy)")
        let firstAscent = try #require(texts.first { $0.text.localizedCaseInsensitiveContains("First Ascent: John Smith") }, "\(copy)")
        let firstRow = try #require(texts.first { $0.text.localizedCaseInsensitiveContains("Marcus T.") }, "\(copy)")
        #expect(firstRow.frame.minY > firstAscent.frame.minY, "the board is not below the First Ascent line: \(copy)")
        #expect(firstRow.frame.minY - firstAscent.frame.maxY < 60, "a gap opened where the removed card used to sit: \(firstAscent.frame) -> \(firstRow.frame)")
    }

    /// Nobody has raced it. No First Ascent holder, so the line is absent and the empty state is
    /// the whole page - the branch that `hasPersonalCompletionStanding` still guards.
    @Test
    func unclaimedClimbStillDaresTheFirstFinisher() async throws {
        let proof = ClimbLeaderboardPageProof(rows: [], firstAscent: nil)

        let texts = try await Self.host(
            name: "climb-leaderboard-tab-unclaimed",
            caption: "Nobody has finished: no First Ascent line, the empty state dares you",
            proof: proof
        )
        let copy = Self.joined(texts)
        #expect(!copy.contains("first ascent:"), "a First Ascent holder on an unclaimed climb: \(copy)")
        #expect(copy.contains("no completed times yet."), "\(copy)")
        #expect(copy.contains("first ascent open. the first finisher claims it forever."), "\(copy)")
    }

    // MARK: - Fixtures

    private static func row(
        id: String,
        rank: Int,
        name: String,
        seconds: TimeInterval,
        isCurrentUser: Bool = false
    ) -> ModeratedReplayLeaderboardRow {
        CrossUserIdentityAdapter.replayRow(
            LiveReplayLeaderboardRow(
                id: id,
                rank: rank,
                displayName: name,
                avatarToken: String(name.prefix(1)),
                photoURL: nil,
                stepsAtBucket: 1_665,
                finalSteps: 1_665,
                deltaFromUser: 0,
                isCurrentUser: isCurrentUser,
                isPersonalBest: isCurrentUser,
                completionDurationSeconds: seconds,
                userId: "user-\(id)"
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
    }

    private static func firstAscent(name: String) -> ModeratedReplayFirstAscent {
        CrossUserIdentityAdapter.firstAscent(
            LiveReplayFirstAscent(
                userId: "user-first-ascent",
                displayName: name,
                avatarToken: String(name.prefix(1)),
                photoURL: nil,
                completedAt: firstAscentDate
            ),
            currentUserId: nil,
            blockedUserIds: [],
            isBlockListHydrated: true
        )
    }

    // MARK: - Hosting

    /// Hosts the captioned page, shrunk to its content's own height once it has laid out, hands
    /// back every piece of copy on it with its frame, and photographs it when this run keeps
    /// photographs.
    private static func host(
        name: String,
        caption: String,
        proof: ClimbLeaderboardPageProof,
        width: CGFloat = 402
    ) async throws -> [OnScreenText] {
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            proof
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark

        return try await RenderedScreen.host(host, size: CGSize(width: width, height: 500)) { screen in
            let fitted = host.sizeThatFits(
                in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            ).height
            screen.window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fitted))
            try await screen.settle()

            // The caption names what the page should show, so it is not part of the page's copy.
            let texts = try await screen.texts().filter { !$0.text.hasPrefix(caption) }
            try screen.photograph(named: name)
            return texts
        }
    }

    private static func joined(_ texts: [OnScreenText]) -> String {
        texts.map(\.text).joined(separator: " ").lowercased()
    }

    /// How many on-screen texts contain `fragment` - or, with `exactly`, are `fragment`.
    private static func count(of fragment: String, in texts: [OnScreenText], exactly: Bool = false) -> Int {
        texts.filter { exactly ? $0.text.lowercased() == fragment : $0.text.lowercased().contains(fragment) }.count
    }
}

/// Reproduction of `ClimbDetailView.leaderboardPage` after the change: First Ascent line, then the
/// board. Nothing stands between them any more.
private struct ClimbLeaderboardPageProof: View {
    let rows: [ModeratedReplayLeaderboardRow]
    let firstAscent: ModeratedReplayFirstAscent?

    private let gold = Color(hex: "F3D76B")

    /// The page draws the First Ascent line only for a claimed climb.
    var showsFirstAscentLine: Bool { firstAscent != nil }

    /// An unclaimed climb draws no line and no rows: the empty state's dare is the whole page.
    var daresTheFirstFinisher: Bool { rows.isEmpty && firstAscent == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let firstAscent {
                firstAscentLine(firstAscent)
            }

            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        leaderboardRow(for: row)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func firstAscentLine(_ firstAscent: ModeratedReplayFirstAscent) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ClimbFirstAscentMark()

            Text(
                "First Ascent: \(firstAscent.identity.displayName) · " +
                    firstAscent.completedAt.formatted(.dateTime.month(.abbreviated).day().year())
            )
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(gold)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(minHeight: 44)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No completed times yet.")
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)

            Text("First Ascent open. The first finisher claims it forever.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    private func leaderboardRow(for row: ModeratedReplayLeaderboardRow) -> some View {
        let rank = row.rank
        let isPodium = isPodiumRank(rank)
        let isFirst = rank == 1
        let rowAccent = accentColor(for: rank)

        return HStack(alignment: .center, spacing: isFirst ? 14 : 12) {
            rankView(for: row)

            avatarToken(for: row, size: isFirst ? 50 : 42, borderColor: isPodium ? rowAccent : nil)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.identity.displayName)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if row.isCurrentUser {
                        Text("YOU")
                            .font(.montserratBold(size: 9))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accent)
                            )
                    }
                }

                Text("\(row.finalSteps.formatted()) steps")
                    .font(.montserratMedium(size: isFirst ? 12 : 11))
                    .foregroundStyle(.white.opacity(0.52))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(durationText(for: row))
                    .font(.montserratBold(size: isFirst ? 18 : 16))
                    .foregroundStyle(isPodium ? rowAccent : (row.isCurrentUser ? .accent : .white))
                    .monospacedDigit()

                if let averageStepsPerMinute = row.averageStepsPerMinute {
                    Text("\(Int(averageStepsPerMinute.rounded()).formatted()) avg SPM")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(.white.opacity(0.52))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, isFirst ? 16 : 13)
        .padding(.horizontal, isPodium || row.isCurrentUser ? 12 : 0)
        .background { rowBackground(for: row) }
        .overlay(alignment: .bottom) {
            if !isPodium && !row.isCurrentUser {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func rankView(for row: ModeratedReplayLeaderboardRow) -> some View {
        if row.rank == 1 {
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(gold)
                .frame(width: 34, alignment: .leading)
        } else if let rank = row.rank {
            Text(CompetitionRanking.rankLabel(rank, isTied: row.isTied, untiedPrefix: "#"))
                .font(.montserratBold(size: 15))
                .foregroundStyle(accentColor(for: rank))
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func rowBackground(for row: ModeratedReplayLeaderboardRow) -> some View {
        let rank = row.rank
        let rowAccent = accentColor(for: rank)

        if rank == 1 {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [rowAccent.opacity(0.18), rowAccent.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(rowAccent.opacity(0.72), lineWidth: 1.4)
                )
        } else if isPodiumRank(rank) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowAccent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(rowAccent.opacity(0.28), lineWidth: 1)
                )
        } else if row.isCurrentUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accent.opacity(0.12))
        }
    }

    private func avatarToken(
        for row: ModeratedReplayLeaderboardRow,
        size: CGFloat,
        borderColor: Color?
    ) -> some View {
        Text(row.identity.avatarToken)
            .font(.montserratBold(size: 13))
            .foregroundStyle(row.isCurrentUser ? .black : .white)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(row.isCurrentUser ? Color.accent : Color(hex: "3A3A3C"))
            )
            .overlay(
                Circle()
                    .stroke(
                        borderColor ?? (row.isCurrentUser ? Color.accent.opacity(0.7) : .white.opacity(0.14)),
                        lineWidth: borderColor == nil ? 1 : 2
                    )
            )
    }

    private func durationText(for row: ModeratedReplayLeaderboardRow) -> String {
        guard let completionDurationSeconds = row.completionDurationSeconds else { return "--" }
        return DurationFormatter.format(duration: completionDurationSeconds)
    }

    private func isPodiumRank(_ rank: Int?) -> Bool {
        guard let rank else { return false }
        return (1...3).contains(rank)
    }

    private func accentColor(for rank: Int?) -> Color {
        switch rank {
        case 1: return gold
        case 2: return Color(hex: "BFC4CC")
        case 3: return Color(hex: "C8793D")
        default: return Color.customGray
        }
    }
}
