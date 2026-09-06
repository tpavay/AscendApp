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

    /// Three champion weeks and one third place. Cumulative bands land on top1 3, top3 4,
    /// top10 4, top100 4 - and no second place at all, which is the lopsided row in a matchup
    /// where both climbers are decorated.
    static let viewerLadder = ProfileAchievementLadder(
        records: [
            achievementRecord(id: "viewer-champion-a", type: .weeklyTop1, rank: 1),
            achievementRecord(id: "viewer-champion-b", type: .monthlyTop1, rank: 1),
            achievementRecord(id: "viewer-champion-c", type: .yearlyTop1, rank: 1),
            achievementRecord(id: "viewer-third", type: .weeklyTop3, rank: 3)
        ]
    )

    /// Every asset the achievement shelf can render, First Ascents included.
    static let shelfAssets = [
        "FirstAscentBadgeDetailed",
        "LeaderboardCrown",
        "LeaderboardSilverMedal",
        "LeaderboardBronzeMedal",
        "LeaderboardTop10",
        "LeaderboardTop100"
    ]

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

    /// A well-earned viewer against a well-earned opponent. Every row carries both sides, and
    /// the side each count belongs to is stated rather than inferred.
    @Test
    func bothClimbersBadgesRenderOnTheirOwnSideOfEveryRow() async throws {
        let elements = try await renderedElements(
            viewer: Self.viewerLadder,
            other: Self.podiumLadder,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, you 3, them 1"))
        #expect(labels.contains("Second place, you 0, them 2"))
        #expect(labels.contains("Third place, you 1, them 1"))
        #expect(labels.contains("TOP 10, you 4, them 5"))
        #expect(labels.contains("TOP 100, you 4, them 6"))
        #expect(labels.contains { $0.hasPrefix("TOP 3,") } == false)
    }

    @Test
    func theLadderRendersInChampionSecondThirdTopTenTopHundredOrder() async throws {
        let elements = try await renderedElements(
            viewer: Self.viewerLadder,
            other: Self.podiumLadder,
            isOtherLoading: false
        )
        // The hosting view reports each row twice; only the first-seen order matters.
        var seen: Set<String> = []
        let rowLabels = elements
            .compactMap(\.accessibilityLabel)
            .filter { $0.contains(", you ") }
            .filter { seen.insert($0).inserted }

        #expect(
            rowLabels == [
                "CHAMPION, you 3, them 1",
                "Second place, you 0, them 2",
                "Third place, you 1, them 1",
                "TOP 10, you 4, them 5",
                "TOP 100, you 4, them 6"
            ]
        )
    }

    /// The defect the captain found: a decorated climber opening a brand-new one's profile used
    /// to see no ACHIEVEMENTS section at all, because the section hid on the *other* side's
    /// emptiness. Their own case is exactly what the comparison is for.
    @Test
    func aDecoratedViewerStillSeesTheirOwnBadgesAgainstAnEmptyClimber() async throws {
        let elements = try await renderedElements(
            viewer: Self.podiumLadder,
            other: .empty,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, you 1, them 0"))
        #expect(labels.contains("Second place, you 2, them 0"))
        #expect(labels.contains("Third place, you 1, them 0"))
        #expect(labels.contains("TOP 10, you 5, them 0"))
        #expect(labels.contains("TOP 100, you 6, them 0"))
    }

    /// The mirror case, which is what shipped as the only case: a new climber looking at a
    /// decorated one still reads the row as theirs against ours, never as an unattributed shelf.
    @Test
    func anEmptyViewerStillSeesTheOtherClimbersBadgesAttributedToThem() async throws {
        let elements = try await renderedElements(
            viewer: .empty,
            other: Self.podiumLadder,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, you 0, them 1"))
        #expect(labels.contains("Second place, you 0, them 2"))
        #expect(labels.contains("Third place, you 0, them 1"))
        #expect(labels.contains("TOP 10, you 0, them 5"))
        #expect(labels.contains("TOP 100, you 0, them 6"))
    }

    @Test
    func twoClimbersWithNoBadgesRenderNoPublicAchievementShell() async throws {
        let elements = try await renderedElements(
            viewer: .empty,
            other: .empty,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("Public profile test host"))
        #expect(labels.contains("Achievements") == false)
        #expect(labels.contains { $0.contains(", you ") } == false)
    }

    @Test
    func loadingAchievementsRenderNothingUntilTheCountsResolve() async throws {
        let elements = try await renderedElements(
            viewer: Self.podiumLadder,
            other: Self.podiumLadder,
            isOtherLoading: true
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("Public profile test host"))
        #expect(labels.contains("Achievements") == false)
        #expect(labels.contains { $0.contains(", you ") } == false)
    }

    /// A public profile whose achievement records did not load can prove its bands but not its
    /// exact placements. A row it cannot answer for is dropped rather than ghosted, because a
    /// ghost would claim a zero nobody read.
    @Test
    func aProfileWithoutRecordsRendersTheBandsAndNoPlacements() async throws {
        let elements = try await renderedElements(
            viewer: Self.podiumLadder,
            other: ProfileAchievementLadder(
                bandedCounters: ProfileAchievementCounts(top1: 2, top3: 9, top10: 14, top100: 30)
            ),
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, you 1, them 2"))
        #expect(labels.contains("TOP 10, you 5, them 14"))
        #expect(labels.contains("TOP 100, you 6, them 30"))
        #expect(labels.contains { $0.hasPrefix("Second place,") } == false)
        #expect(labels.contains { $0.hasPrefix("Third place,") } == false)
        #expect(labels.contains { $0.hasPrefix("TOP 3,") } == false)
    }

    /// A ladder nobody read is not a ladder of zeros. The row still belongs to the climber whose
    /// count is real, and the unreadable side reads as a dash - the same neutral mark the PROFILE
    /// rows already use for a value this screen does not have.
    @Test
    func anUnreadableViewerLadderReadsAsUnknownRatherThanZero() async throws {
        let elements = try await renderedElements(
            viewer: .unreadable,
            other: Self.podiumLadder,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, you unknown, them 1"))
        #expect(labels.contains("Second place, you unknown, them 2"))
        #expect(labels.contains("TOP 100, you unknown, them 6"))
        #expect(labels.contains { $0.hasPrefix("CHAMPION, you 0") } == false)
    }

    @Test
    func anUnreadableOtherLadderReadsAsUnknownRatherThanZero() async throws {
        let elements = try await renderedElements(
            viewer: Self.podiumLadder,
            other: .unreadable,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, you 1, them unknown"))
        #expect(labels.contains("TOP 100, you 6, them unknown"))
        #expect(labels.contains { $0.hasSuffix("them 0") } == false)
    }

    /// Neither side is known to hold anything, so there is nothing to compare and no shell.
    @Test
    func twoUnreadableLaddersRenderNoPublicAchievementShell() async throws {
        let elements = try await renderedElements(
            viewer: .unreadable,
            other: .unreadable,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("Public profile test host"))
        #expect(labels.contains("Achievements") == false)
        #expect(labels.contains { $0.contains(", you ") } == false)
    }

    @Test
    func publicComparisonRowsNeverOpenAchievementHistory() async throws {
        let elements = try await renderedElements(
            viewer: Self.viewerLadder,
            other: Self.podiumLadder,
            isOtherLoading: false
        )
        let champion = try #require(
            elements.first { $0.accessibilityLabel == "CHAMPION, you 3, them 1" }
        )
        let secondPlace = try #require(
            elements.first { $0.accessibilityLabel == "Second place, you 0, them 2" }
        )

        #expect(champion.accessibilityTraits.contains(.button) == false)
        #expect(secondPlace.accessibilityTraits.contains(.button) == false)
    }

    @Test
    func ownProfileBadgesStayTappableWithNoFinalizedRows() async throws {
        let elements = try await renderedElements(
            hosting: ProfilePrestigeBadgeShelf(
                tokens: ProfilePrestigeToken.tokens(
            for: ProfileAchievementTally(ladder: Self.podiumLadder),
            surface: .ownProfile
        ),
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

    /// The crown draws at its shelf size - a 1x lay-out of the badge proves it puts paint down -
    /// and the size-comparison sheet is photographed only under `ASCEND_EVIDENCE_DIR`.
    @Test
    func crownAndPrestigeTokensProduceReviewablePixels() throws {
        let tokens = ProfilePrestigeToken.tokens(
            for: ProfileAchievementTally(ladder: Self.podiumLadder),
            surface: .ownProfile
        )
        let crown = try #require(tokens.first)
        #expect(crown.id == "top1")

        try RenderedScreen.withOffscreenPixels(
            of: ProfilePrestigeBadgeView(token: crown, imageSize: 54)
        ) { pixels in
            #expect(pixels.bounds { $0.alpha > 0 } != nil, "the crown drew nothing at 54pt")
        }

        guard RenderedScreen.isPhotographing else { return }
        try RenderedScreen.photograph(
            VStack(alignment: .leading, spacing: 24) {
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
            // Wide enough for all five ladder badges: the shelf scrolls in the app, but a
            // clipped evidence image proves nothing about the badge that fell off its edge.
            .frame(width: 500, height: 410, alignment: .topLeading)
            .background(ProfileVisualStyle.background),
            named: "crown-and-prestige-tokens"
        )
    }

    /// The shelf is free-standing cut-out art on every badge. Template rendering would throw the
    /// colour away and stamp a flat silhouette, and an opaque backing would reintroduce the tile
    /// the frame removal just deleted - both have to fail here rather than in review.
    @Test
    func everyShelfBadgeShipsAsFreeStandingColourArt() throws {
        for asset in Self.shelfAssets {
            let image = try #require(UIImage(named: asset), "\(asset) is missing from the catalogue")

            #expect(
                image.renderingMode == .alwaysOriginal,
                "\(asset) must declare template-rendering-intent original"
            )

            let cgImage = try #require(image.cgImage, "\(asset) has no bitmap")
            let alphaInfo = cgImage.alphaInfo
            #expect(
                alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast,
                "\(asset) carries no alpha channel"
            )

            let corners = try cornerAlpha(of: cgImage)
            #expect(corners.allSatisfy { $0 == 0 }, "\(asset) is opaque-backed: corner alpha \(corners)")
        }
    }

    /// TOP 10 and TOP 100 render at 46pt and 54pt and nowhere else, so 512px on the long edge is
    /// well clear of the 54pt @3x ceiling. A future replacement that lands at source resolution
    /// bloats the bundle for no rendered pixel.
    @Test
    func theBandBadgesCarryShelfSizedArt() throws {
        for asset in ["LeaderboardTop10", "LeaderboardTop100"] {
            let image = try #require(UIImage(named: asset))
            let longEdge = max(image.size.width, image.size.height) * image.scale

            #expect(longEdge == 512, "\(asset) is \(longEdge)px on the long edge, expected 512")
        }
    }

    /// Each band badge puts paint down at both shelf sizes, read off a 1x lay-out; the
    /// comparison sheet is photographed only under `ASCEND_EVIDENCE_DIR`.
    @Test
    func theBandBadgesProduceReviewablePixelsAtShelfSizes() throws {
        let tokens = ProfilePrestigeToken.tokens(
            for: ProfileAchievementTally(ladder: Self.podiumLadder),
            surface: .ownProfile
        )
        let crown = try #require(tokens.first { $0.id == "top1" })
        let topTen = try #require(tokens.first { $0.id == "top10" })
        let topHundred = try #require(tokens.first { $0.id == "top100" })

        for token in [topTen, topHundred] {
            for size in [CGFloat(46), CGFloat(54)] {
                try RenderedScreen.withOffscreenPixels(
                    of: ProfilePrestigeBadgeView(token: token, imageSize: size)
                ) { pixels in
                    #expect(
                        pixels.bounds { $0.alpha > 0 } != nil,
                        "\(token.id) drew nothing at \(Int(size))pt"
                    )
                }
            }
        }

        guard RenderedScreen.isPhotographing else { return }
        try RenderedScreen.photograph(
            VStack(alignment: .leading, spacing: 20) {
                Text("BAND BADGES ON THE SHELF")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)

                ForEach([CGFloat(46), CGFloat(54)], id: \.self) { size in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(size)) PT - PUBLIC PROFILE\(size == 54 ? " / OWN PROFILE" : "")")
                            .font(.montserratSemiBold(size: 9))
                            .foregroundStyle(ProfileVisualStyle.secondaryText)

                        HStack(alignment: .top, spacing: 4) {
                            ProfilePrestigeBadgeView(token: crown, imageSize: size)
                            ProfilePrestigeBadgeView(token: topTen, imageSize: size)
                            ProfilePrestigeBadgeView(token: topHundred, imageSize: size)
                        }
                    }
                }

                Text("TRANSPARENCY CHECK - AN OPAQUE BACKING WOULD SHOW AS A BOX")
                    .font(.montserratSemiBold(size: 9))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)

                HStack(alignment: .top, spacing: 4) {
                    ProfilePrestigeBadgeView(token: topTen, imageSize: 54)
                    ProfilePrestigeBadgeView(token: topHundred, imageSize: 54)
                }
                .padding(8)
                .background(Color.ascendAccent)
            }
            .padding(20)
            .frame(width: 420, height: 520, alignment: .topLeading)
            .background(ProfileVisualStyle.background),
            named: "band-badges-at-shelf-sizes"
        )
    }

    /// The podium seats the three entries on their own ranks; the crown row is photographed
    /// only under `ASCEND_EVIDENCE_DIR`.
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
        let podiumEntries = ModeratedLeaderboardPodiumLayout.podiumEntries(from: entries)
        #expect(podiumEntries.map(\.rank) == [1, 2, 3])

        guard RenderedScreen.isPhotographing else { return }
        try RenderedScreen.photograph(
            LeaderboardPodiumView(entries: podiumEntries, metric: .climb)
                .padding(16)
                .frame(width: 390, height: 260, alignment: .bottom)
                .background(Color.black)
                .environment(\.colorScheme, .dark),
            named: "podium-champion-crown-row"
        )
    }

    /// The empty board hosted as it ships: the window is named as empty and the dare to take
    /// first is on screen, read off the accessibility tree. Photographed only under
    /// `ASCEND_EVIDENCE_DIR`.
    @Test
    func unclaimedFirstPlaceSeatsTheCrownInsideTheOpenPedestal() async throws {
        let size = CGSize(width: 390, height: 340)
        try await RenderedScreen.host(
            LeaderboardEmptyBoardView(
                period: LeaderboardPeriod(
                    timeFrame: .monthly,
                    key: "2026-M08",
                    startAt: Date(timeIntervalSince1970: 1_754_006_400),
                    endAt: Date(timeIntervalSince1970: 1_756_684_800)
                ),
                metric: .climb
            )
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            let text = try await screen.copy { $0.contains("take the first spot") }
            #expect(text.contains("is empty"))
            #expect(text.contains("take the first spot"))
            try screen.photograph(named: "leaderboard-empty-board-crown")
        }
    }

    /// Alpha at the four corners of a catalogue asset, read out of a premultiplied buffer -
    /// CoreGraphics offers no straight-alpha 8-bit context, and alpha itself is unaffected by
    /// the premultiply. The asset is the app's own input, not a render.
    private func cornerAlpha(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)

        return [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
            .map { x, y in pixels[(y * width + x) * 4 + 3] }
    }

    private func renderedElements(
        viewer: ProfileAchievementLadder = .empty,
        other: ProfileAchievementLadder,
        isOtherLoading: Bool
    ) async throws -> [NSObject] {
        try await renderedElements(
            hosting: PublicProfileAchievementsSection(
                viewer: ProfileAchievementTally(ladder: viewer),
                other: ProfileAchievementTally(ladder: other),
                isOtherLoading: isOtherLoading
            )
        )
    }

    /// Hosts `section` under a labelled marker through `RenderedScreen` and returns the settled
    /// accessibility tree once that marker has arrived.
    private func renderedElements(
        hosting section: some View
    ) async throws -> [NSObject] {
        let size = CGSize(width: 402, height: 300)
        return try await RenderedScreen.host(
            VStack(alignment: .leading, spacing: 30) {
                Text("Public profile test host")
                    .accessibilityLabel("Public profile test host")

                section
            }
            .padding(20)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(ProfileVisualStyle.background),
            size: size
        ) { screen in
            try await screen.elements { elements in
                elements.contains {
                    $0.accessibilityLabel == "Public profile test host"
                }
            }
        }
    }
}
