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
/// Drawn through a live `UIWindow` rather than `ImageRenderer`, which draws asset-catalogue art in
/// a nested layout as blank.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbLeaderboardTabVisualEvidenceTests {
    private static let firstAscentDate = Date(timeIntervalSince1970: 1_754_870_400)

    /// The captain's Charminar case: he is the only finisher, so his row is the whole board. The
    /// "Your best / 02:06 · #1 of 1" card used to sit directly above this row saying the same two
    /// numbers.
    @Test
    func soleFinisherSeesOneRowAndNoDuplicateSummary() throws {
        try Self.capture(
            name: "climb-leaderboard-tab-sole-finisher",
            caption: "Raced it, only finisher: one row, YOU pill, rank and time stated once",
            rows: [Self.row(id: "you", rank: 1, name: "Tyler P.", seconds: 126, isCurrentUser: true)]
        )
    }

    /// The same climber further down a real field. Their row is the only place their time and rank
    /// appear, and the YOU pill is what finds it.
    @Test
    func rankedClimberKeepsTheYouPillOnTheirOwnRow() throws {
        try Self.capture(
            name: "climb-leaderboard-tab-raced",
            caption: "Raced it, mid-field: the YOU pill is the only marker of your own row",
            rows: [
                Self.row(id: "1", rank: 1, name: "Marcus T.", seconds: 104),
                Self.row(id: "2", rank: 2, name: "Priya S.", seconds: 118),
                Self.row(id: "3", rank: 3, name: "Dana R.", seconds: 121),
                Self.row(id: "4", rank: 4, name: "Tyler P.", seconds: 126, isCurrentUser: true),
                Self.row(id: "5", rank: 5, name: "Owen B.", seconds: 140)
            ]
        )
    }

    /// Never raced it. The removed card never rendered in this state, so the only question the
    /// photograph answers is whether the page still holds together above the board.
    @Test
    func climberWhoHasNotRacedStillGetsAWholePage() throws {
        try Self.capture(
            name: "climb-leaderboard-tab-not-raced",
            caption: "Never raced it: First Ascent line runs straight into the board, no gap left behind",
            rows: [
                Self.row(id: "1", rank: 1, name: "Marcus T.", seconds: 104),
                Self.row(id: "2", rank: 2, name: "Priya S.", seconds: 118),
                Self.row(id: "3", rank: 3, name: "Dana R.", seconds: 121),
                Self.row(id: "4", rank: 4, name: "Owen B.", seconds: 140)
            ]
        )
    }

    /// Nobody has raced it. No First Ascent holder, so the line is absent and the empty state is
    /// the whole page - the branch that `hasPersonalCompletionStanding` still guards.
    @Test
    func unclaimedClimbStillDaresTheFirstFinisher() throws {
        try Self.capture(
            name: "climb-leaderboard-tab-unclaimed",
            caption: "Nobody has finished: no First Ascent line, the empty state dares you",
            rows: [],
            firstAscentHolder: nil
        )
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

    // MARK: - Capture

    private static func capture(
        name: String,
        caption: String,
        rows: [ModeratedReplayLeaderboardRow],
        firstAscentHolder: ModeratedReplayFirstAscent? = firstAscent(name: "John Smith"),
        width: CGFloat = 402
    ) throws {
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            ClimbLeaderboardPageProof(rows: rows, firstAscent: firstAscentHolder)
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark
        let window = try makeWindow(host: host, width: width)
        defer { tearDown(window) }

        var fitted: CGFloat = 400
        for _ in 0..<10 {
            pump(window)
            fitted = host.sizeThatFits(
                in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            ).height
        }

        try write(draw(window, width: width, fittingHeight: fitted), name: name)
    }

    private static func makeWindow(
        host: UIHostingController<some View>,
        width: CGFloat
    ) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 500)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    private static func pump(_ window: UIWindow) {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    private static func draw(
        _ window: UIWindow,
        width: CGFloat,
        fittingHeight: CGFloat
    ) -> UIImage {
        window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fittingHeight))
        pump(window)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private static func tearDown(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }

    private static func write(_ image: UIImage, name: String) throws {
        let data = try #require(image.pngData(), "No PNG data for \(name)")
        let candidates = [
            ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"],
            NSTemporaryDirectory().appending("ascend-climb-leaderboard-evidence")
        ].compactMap { $0 }

        for directory in candidates {
            let url = URL(filePath: directory).appending(path: "\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: URL(filePath: directory),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
                print("ASCEND_EVIDENCE_PNG \(url.path)")
                return
            } catch {
                continue
            }
        }
        Issue.record("No writable evidence directory for \(name)")
    }
}

/// Reproduction of `ClimbDetailView.leaderboardPage` after the change: First Ascent line, then the
/// board. Nothing stands between them any more.
private struct ClimbLeaderboardPageProof: View {
    let rows: [ModeratedReplayLeaderboardRow]
    let firstAscent: ModeratedReplayFirstAscent?

    private let gold = Color(hex: "F3D76B")

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
