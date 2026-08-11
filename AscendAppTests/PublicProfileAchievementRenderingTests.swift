import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct PublicProfileAchievementRenderingTests {
    /// One champion week, two seconds, one third, one top-ten and one top-hundred finish.
    /// Cumulative bands land on top1 1, top3 4, top10 5, top100 6.
    static let podiumLadder = ProfileAchievementLadder(
        records: [
            achievementRecord(id: "champion", type: .weeklyTop1, rank: 1),
            achievementRecord(id: "second-a", type: .monthlyTop3, rank: 2),
            achievementRecord(id: "second-b", type: .yearlyTop3, rank: 2),
            achievementRecord(id: "third", type: .weeklyTop3, rank: 3),
            achievementRecord(id: "top-ten", type: .weeklyTop10, rank: 7),
            achievementRecord(id: "top-hundred", type: .weeklyTop100, rank: 55)
        ]
    )

    static func achievementRecord(
        id: String,
        type: ProfileAchievementType,
        rank: Int?
    ) -> ProfileAchievementRecord {
        ProfileAchievementRecord(
            id: id,
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: nil,
            periodStartAt: nil,
            periodEndAt: nil,
            earnedAt: Date(timeIntervalSince1970: 1_754_000_000),
            rank: rank,
            value: 12_000,
            valueUnit: "steps"
        )
    }

    @Test
    func presentAchievementsRenderTheOtherClimbersExactPlacementsAndBandCounts() async throws {
        let elements = try await renderedElements(
            achievements: Self.podiumLadder,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, 1"))
        #expect(labels.contains("Second place, 2"))
        #expect(labels.contains("Third place, 1"))
        #expect(labels.contains("TOP 10, 5"))
        #expect(labels.contains("TOP 100, 6"))
        #expect(labels.contains { $0.hasPrefix("TOP 3,") } == false)
    }

    @Test
    func theLadderRendersInChampionSecondThirdTopTenTopHundredOrder() async throws {
        let elements = try await renderedElements(
            achievements: Self.podiumLadder,
            isOtherLoading: false
        )
        // The hosting scroll view reports each badge twice; only the first-seen order matters.
        var seen: Set<String> = []
        let badgeLabels = elements
            .compactMap(\.accessibilityLabel)
            .filter { $0.contains(", ") && $0 != "Public profile test host" }
            .filter { seen.insert($0).inserted }

        #expect(
            badgeLabels == [
                "CHAMPION, 1",
                "Second place, 2",
                "Third place, 1",
                "TOP 10, 5",
                "TOP 100, 6"
            ]
        )
    }

    @Test
    func absentAchievementsRenderNoPublicAchievementShell() async throws {
        let elements = try await renderedElements(
            achievements: .empty,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("Public profile test host"))
        #expect(labels.contains("Achievements") == false)
        #expect(labels.contains { $0.hasPrefix("CHAMPION,") } == false)
        #expect(labels.contains { $0.hasPrefix("TOP ") } == false)
        #expect(labels.contains { $0.hasPrefix("Second place,") } == false)
        #expect(labels.contains { $0.hasPrefix("Third place,") } == false)
    }

    @Test
    func loadingAchievementsRenderNothingUntilTheCountsResolve() async throws {
        let elements = try await renderedElements(
            achievements: Self.podiumLadder,
            isOtherLoading: true
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("Public profile test host"))
        #expect(labels.contains("Achievements") == false)
        #expect(labels.contains { $0.hasPrefix("CHAMPION,") } == false)
        #expect(labels.contains { $0.hasPrefix("TOP ") } == false)
        #expect(labels.contains { $0.hasPrefix("Second place,") } == false)
        #expect(labels.contains { $0.hasPrefix("Third place,") } == false)
    }

    /// A public profile whose achievement records did not load renders only the badges its
    /// banded counters can prove. It never guesses a second place apart from a third.
    @Test
    func aProfileWithoutRecordsRendersTheBandsAndNoPlacements() async throws {
        let elements = try await renderedElements(
            achievements: ProfileAchievementLadder(
                bandedCounters: ProfileAchievementCounts(top1: 2, top3: 9, top10: 14, top100: 30)
            ),
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, 2"))
        #expect(labels.contains("TOP 10, 14"))
        #expect(labels.contains("TOP 100, 30"))
        #expect(labels.contains { $0.hasPrefix("Second place,") } == false)
        #expect(labels.contains { $0.hasPrefix("Third place,") } == false)
        #expect(labels.contains { $0.hasPrefix("TOP 3,") } == false)
    }

    @Test
    func publicBadgesNeverOpenAchievementHistory() async throws {
        let elements = try await renderedElements(
            achievements: Self.podiumLadder,
            isOtherLoading: false
        )
        let champion = try #require(
            elements.first { $0.accessibilityLabel == "CHAMPION, 1" }
        )
        let secondPlace = try #require(
            elements.first { $0.accessibilityLabel == "Second place, 2" }
        )

        #expect(champion.accessibilityTraits.contains(.button) == false)
        #expect(secondPlace.accessibilityTraits.contains(.button) == false)
    }

    @Test
    func ownProfileBadgesStayTappableWithNoFinalizedRows() async throws {
        let elements = try await renderedElements(
            hosting: ProfilePrestigeBadgeShelf(
                tokens: ProfilePrestigeToken.leaderboardTokens(for: Self.podiumLadder),
                imageSize: 54,
                history: []
            )
        )
        let champion = try #require(
            elements.first { $0.accessibilityLabel == "CHAMPION, 1" }
        )
        let secondPlace = try #require(
            elements.first { $0.accessibilityLabel == "Second place, 2" }
        )

        #expect(champion.accessibilityTraits.contains(.button))
        #expect(secondPlace.accessibilityTraits.contains(.button))
    }

    @Test
    func crownAndPrestigeTokensProduceReviewablePixels() throws {
        let tokens = ProfilePrestigeToken.leaderboardTokens(for: Self.podiumLadder)
        let crown = try #require(tokens.first)
        let renderer = ImageRenderer(
            content: VStack(alignment: .leading, spacing: 24) {
                Text("CROWN SIZE CHECK")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)

                HStack(alignment: .bottom, spacing: 30) {
                    VStack(spacing: 8) {
                        Image("LeaderboardCrown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text("16 PT")
                    }

                    VStack(spacing: 8) {
                        Image("LeaderboardCrown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                        Text("30 PT")
                    }

                    ProfilePrestigeBadgeView(token: crown, imageSize: 46)
                    ProfilePrestigeBadgeView(token: crown, imageSize: 54)
                }
                .font(.montserratSemiBold(size: 9))
                .foregroundStyle(ProfileVisualStyle.secondaryText)

                Text("THE LADDER")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)

                HStack(alignment: .top, spacing: 4) {
                    ForEach(tokens) { token in
                        ProfilePrestigeBadgeView(token: token, imageSize: 54)
                    }
                }
            }
            .padding(20)
            .frame(width: 420, height: 410, alignment: .topLeading)
            .background(ProfileVisualStyle.background)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage)
        let png = try #require(image.pngData())
        let url = URL.temporaryDirectory.appending(path: "crown-and-prestige-tokens.png")
        try png.write(to: url, options: .atomic)

        print("ASCEND_EVIDENCE_PNG \(url.path)")
    }

    @Test
    func podiumCrownSitsAboveTheChampionAvatarOnItsOwnRow() throws {
        let entries = [
            ("Dana R.", 1, 21_482),
            ("Priya S.", 2, 19_812),
            ("Marcus T.", 3, 17_926)
        ].map { name, rank, steps in
            CrossUserIdentityAdapter.leaderboardEntry(
                LeaderboardEntry(
                    userId: "user-\(rank)",
                    displayName: name,
                    rank: rank,
                    value: Double(steps),
                    formattedValue: steps.formatted(),
                    isCurrentUser: false,
                    isTied: false
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let renderer = ImageRenderer(
            content: LeaderboardPodiumView(
                entries: ModeratedLeaderboardPodiumLayout.podiumEntries(from: entries),
                metric: .climb
            )
            .padding(16)
            .frame(width: 390, height: 260, alignment: .bottom)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage)
        let png = try #require(image.pngData())
        let url = URL.temporaryDirectory.appending(path: "podium-champion-crown-row.png")
        try png.write(to: url, options: .atomic)

        print("ASCEND_EVIDENCE_PNG \(url.path)")
    }

    @Test
    func unclaimedFirstPlaceSeatsTheCrownInsideTheOpenPedestal() throws {
        let renderer = ImageRenderer(
            content: LeaderboardEmptyBoardView(
                period: LeaderboardPeriod(
                    timeFrame: .monthly,
                    key: "2026-M08",
                    startAt: Date(timeIntervalSince1970: 1_754_006_400),
                    endAt: Date(timeIntervalSince1970: 1_756_684_800)
                ),
                metric: .climb
            )
            .frame(width: 390, height: 340, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage)
        let png = try #require(image.pngData())
        let url = URL.temporaryDirectory.appending(path: "leaderboard-empty-board-crown.png")
        try png.write(to: url, options: .atomic)

        print("ASCEND_EVIDENCE_PNG \(url.path)")
    }

    private func renderedElements(
        achievements: ProfileAchievementLadder,
        isOtherLoading: Bool
    ) async throws -> [NSObject] {
        try await renderedElements(
            hosting: PublicProfileAchievementsSection(
                achievements: achievements,
                isOtherLoading: isOtherLoading
            )
        )
    }

    private func renderedElements(
        hosting section: some View
    ) async throws -> [NSObject] {
        try await withAccessibilityAutomation {
            let size = CGSize(width: 402, height: 300)
            let controller = UIHostingController(
                rootView: VStack(alignment: .leading, spacing: 30) {
                    Text("Public profile test host")
                        .accessibilityLabel("Public profile test host")

                    section
                }
                .padding(20)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(ProfileVisualStyle.background)
            )
            controller.overrideUserInterfaceStyle = .dark
            controller.view.frame = CGRect(origin: .zero, size: size)

            let scene = try #require(
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first,
                "The hosted public profile needs an active window scene"
            )
            let window = UIWindow(windowScene: scene)
            window.frame = controller.view.frame
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            return try await settledAccessibilityElements(
                under: controller.view,
                until: { elements in
                    elements.contains {
                        $0.accessibilityLabel == "Public profile test host"
                    }
                }
            )
        }
    }
}
