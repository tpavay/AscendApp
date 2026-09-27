import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence that a champion's crown sits on their picture on every surface that shows one,
/// is hidden where a medal ring already shows, and takes each title's colour.
///
/// Every render is the shipping view, hosted through `RenderedScreen` with a
/// `ChampionRegistry` holding fixture reigns. The crown is proved on pixels - its drawn
/// ink inside the perch the picture's size calls for - because it is decoration the
/// accessibility tree deliberately hides. Photographs land in `ASCEND_EVIDENCE_DIR` when
/// it is set.
@MainActor
@Suite(.hostsAWindow)
struct ChampionCrownEvidenceTests {
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 24, hour: 18)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private let fixtures = ChampionRecapFixtures(viewerId: "viewer", viewerName: "Tyler Pavay", now: Self.now)

    /// A registry crowning `fixture-zoe` weekly, `fixture-ezra` monthly, `fixture-vera` yearly,
    /// and `double` with the month and the week.
    private func registry(repository: FakeLeaderboardResults = FakeLeaderboardResults()) -> ChampionRegistry {
        let registry = ChampionRegistry(repository: repository, isFeatureEnabled: { true }, clock: { Self.now })
        var reigns: [ChampionTitle: ChampionReign] = [:]
        let (week, month) = fixtures.periods()
        let year = LeaderboardTimeFrame.yearly.previousPeriod(referenceDate: Self.now)!
        for (title, period, champions) in [
            (ChampionTitle.weekly, week, ["fixture-zoe", "double"]),
            (.monthly, month, ["fixture-ezra", "double"]),
            (.yearly, year, ["fixture-vera"])
        ] {
            let result = LeaderboardResult(
                period: period,
                climberCount: 12,
                championUserIds: champions,
                podiumUserIds: champions,
                mostClimbs: nil,
                community: .empty
            )
            reigns[title] = ChampionReign(title: title, result: result, champions: [])
        }
        registry.apply(reigns)
        return registry
    }

    // MARK: - The shared picture

    @Test
    func everyTitleWearsItsOwnCrownAtEverySurfaceSize() async throws {
        let registry = registry()
        let sizes: [CGFloat] = [120, 88, 76, 50, 44, 42, 38, 32]
        for size in sizes {
            for (userId, title) in [("fixture-zoe", ChampionTitle.weekly), ("fixture-ezra", .monthly), ("fixture-vera", .yearly)] {
                let ink = try await crownInk(userId: userId, size: size, registry: registry)
                #expect(ink.inPerch > 12, "no \(title) crown on a \(Int(size))pt picture (\(ink.inPerch) ink pixels)")
            }
            let bare = try await crownInk(userId: "fixture-maya", size: size, registry: registry)
            #expect(bare.inPerch == 0, "a \(Int(size))pt picture with no title drew a crown")
            let suppressed = try await crownInk(userId: "fixture-zoe", size: size, registry: registry, showsMark: false)
            #expect(suppressed.inPerch == 0, "a ring-wearing \(Int(size))pt picture still drew its crown")
        }
    }

    @Test
    func aBlockedChampionKeepsTheCrownOnThePlaceholder() async throws {
        let blocked = CrossUserIdentityResolver.resolve(
            userId: "fixture-zoe",
            displayName: "Zoe Ramirez",
            photoURL: nil,
            isCurrentUser: false,
            blockedUserIds: ["fixture-zoe"],
            isBlockListHydrated: true
        )
        #expect(blocked.isHidden)
        let ink = try await crownInk(
            userId: blocked.userId,
            size: 44,
            registry: registry(),
            placeholder: .initials(for: blocked, fill: Color(hex: "3A3A3C"))
        )
        #expect(ink.inPerch > 12)
    }

    @Test
    func theGalleryOfCrownedPictures() async throws {
        let registry = registry()
        let size = CGSize(width: 402, height: 560)
        try await RenderedScreen.host(
            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 40) {
                    avatar("fixture-zoe", 120, label: "Settings")
                    avatar("double", 88, label: "Profile, two titles")
                    avatar("fixture-vera", 76, label: "Comparison")
                }
                HStack(spacing: 30) {
                    avatar("fixture-zoe", 50, label: "ALL TIMES")
                    avatar("fixture-ezra", 44, label: "Live race")
                    avatar("fixture-vera", 42, label: "Pinned row")
                    avatar("fixture-zoe", 38, label: "Home feed")
                    avatar("fixture-ezra", 32, label: "Recap row")
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 24)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color.black)
            .environment(registry)
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            #expect(try await screen.copy().contains("two titles"))
            try screen.photograph(named: "champion-crown-gallery")
        }
    }

    // MARK: - Surfaces

    @Test
    func thePinnedRowWearsTheCompactCrownAndTheLastDayTurnsGold() async throws {
        let entry = CrossUserIdentityAdapter.leaderboardEntry(
            LeaderboardEntry(
                userId: "fixture-zoe",
                displayName: "Zoe Ramirez",
                rank: 9,
                value: 1_402,
                formattedValue: "1,402",
                isCurrentUser: true
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        let week = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: Self.now)
        let lastDay = week.endAt!.addingTimeInterval(-4 * 3_600 - 12 * 60)
        let size = CGSize(width: 402, height: 110)
        try await RenderedScreen.host(
            LeaderboardUserRowView(
                entry: entry,
                metric: .climb,
                crownGapText: "516 STEPS TO CROWN",
                countdownPeriod: week,
                now: lastDay
            )
            .padding(.top, 20)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(registry())
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("516 steps to crown · 4h 12m left"), "\(copy)")
            try screen.photograph(named: "champion-pinned-row-last-day")
        }
    }

    @Test
    func thePodiumHidesThePerchedCrownAndFirstPlaceTakesTheBoardsColour() async throws {
        let entries = ["fixture-maya", "fixture-ezra", "fixture-noah"].enumerated().map { index, userId in
            CrossUserIdentityAdapter.leaderboardEntry(
                LeaderboardEntry(
                    userId: userId,
                    displayName: ChampionRecapFixtures.names.first { $0.id == userId }?.name ?? userId,
                    rank: [2, 1, 3][index],
                    value: Double([6_904, 7_420, 6_310][index]),
                    formattedValue: [6_904, 7_420, 6_310][index].formatted()
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }.sorted { $0.rank < $1.rank }

        for title in ChampionTitle.allCases {
            let size = CGSize(width: 402, height: 260)
            try await RenderedScreen.host(
                NavigationStack {
                    LeaderboardPodiumView(entries: entries, metric: .climb, awardedTitle: title)
                }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(Color.black)
                    .environment(registry())
                    .environment(\.colorScheme, .dark),
                size: size
            ) { screen in
                // fixture-ezra (the monthly champion) stands first; the podium's floating crown
                // is the only crown there, so nothing perches at the picture's top right.
                let copy = try await screen.copy()
                #expect(copy.contains("ezra kim"))
                try screen.photograph(named: "champion-podium-\(title.rawValue)")
            }
        }
    }

    @Test
    func theCompletionBoardCrownsARowButNotAMedalRow() async throws {
        let rows = [
            ("fixture-maya", "Maya Chen", 1, 1_665, 104.0),
            ("fixture-zoe", "Zoe Ramirez", 2, 1_665, 118.0),
            ("fixture-noah", "Noah Grant", 3, 1_665, 126.0),
            ("fixture-ezra", "Ezra Kim", 4, 1_665, 140.0)
        ].map { userId, name, rank, steps, duration in
            CrossUserIdentityAdapter.replayRow(
                LiveReplayLeaderboardRow(
                    id: userId,
                    rank: rank,
                    displayName: name,
                    avatarToken: "",
                    photoURL: nil,
                    stepsAtBucket: steps,
                    finalSteps: steps,
                    deltaFromUser: 0,
                    isCurrentUser: false,
                    isPersonalBest: false,
                    completionDurationSeconds: duration,
                    userId: userId,
                    gender: nil,
                    age: nil,
                    locationCity: nil
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let size = CGSize(width: 402, height: 420)
        try await RenderedScreen.host(
            NavigationStack {
            ReplayCompletionLeaderboardView(
                rows: rows,
                completedCount: rows.count,
                isLoading: false,
                fetchFailed: false,
                currentUserPhotoURL: nil,
                effectiveColorScheme: .dark,
                emptyTitle: "No completed times yet.",
                emptyMessage: "",
                emphasis: .duration
            )
            }
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(registry())
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            #expect(try await screen.copy().contains("ezra kim"))
            try screen.photograph(named: "champion-completion-board")
        }
    }

    @Test
    func theHomeFeedRowWearsTheCrown() async throws {
        let publishedAt = Self.now.addingTimeInterval(-120)
        let row = CrossUserIdentityAdapter.homeTodayRow(
            HomeTodayActivityRow(
                workoutId: "w1",
                userId: "fixture-ezra",
                kind: .justClimb,
                climbId: nil,
                attemptClimbId: nil,
                routineTemplateId: nil,
                steps: 1_665,
                durationSeconds: 768,
                completedAt: publishedAt,
                publishedAt: publishedAt,
                justClimbGoalKind: nil,
                justClimbGoalValue: nil,
                isPartial: false,
                targetSteps: nil,
                targetDurationSeconds: nil,
                displayName: "Ezra Kim",
                photoURL: nil,
                avatarToken: "EK",
                isSynthetic: false
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        let presentation = HomeTodayActivityRowPresentation(
            row: row,
            climbName: nil,
            routineTemplateName: nil,
            now: Self.now
        )
        let size = CGSize(width: 402, height: 160)
        try await RenderedScreen.host(
            HomeTodayActivitySection(
                rows: [row],
                presentations: [row.id: presentation],
                hasReceivedFeed: true,
                showsSeeAll: false,
                onOpen: { _, _ in },
                onSeeAll: {}
            )
            .padding(20)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(registry())
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            #expect(try await screen.copy().contains("ezra kim"))
            try screen.photograph(named: "champion-home-feed-row")
        }
    }

    @Test
    func homesWeeklyRankTileCountsDownTheWeek() async throws {
        let summary = HomeWeeklyRankSummary(
            rank: 9,
            population: 38,
            isTiedForGold: false,
            stepsAheadOfSecond: nil,
            stepsFromGold: nil,
            stepsFromSilver: nil,
            stepsToBronze: 1_618,
            stepsToTop10: nil,
            stepsToTop100: nil,
            stepsToTop50Percent: nil
        )
        let week = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: Self.now)
        for (name, now) in [
            ("thursday", Self.now),
            ("last-day", week.endAt!.addingTimeInterval(-4 * 3_600 - 12 * 60))
        ] {
            let size = CGSize(width: 402, height: 170)
            try await RenderedScreen.host(
                HomeRankStreakSection(
                    weeklyRankSummary: summary,
                    isRankLoading: false,
                    streak: WeeklyStreak(weeks: 4, isCurrentWeekSecured: false),
                    now: now,
                    onRankTapped: {},
                    onStreakTapped: {}
                )
                .padding(20)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark),
                size: size
            ) { screen in
                try screen.photograph(named: "champion-home-rank-tile-\(name)")
            }
        }
        #expect(LeaderboardCountdown.make(period: week, now: Self.now)?.text == "ENDS IN 3D 6H")
    }

    @Test
    func yourProfileWearsTheLeadingCrownAndADotPerOtherTitle() async throws {
        let identity = CrossUserIdentityResolver.resolve(
            userId: "double",
            displayName: "Tyler Pavay",
            photoURL: nil,
            isCurrentUser: true,
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        let size = CGSize(width: 402, height: 220)
        try await RenderedScreen.host(
            NavigationStack {
                IdentityHeroSection(snapshot: Self.snapshot(userId: "double"), identity: identity)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(registry())
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            #expect(try await screen.copy().contains("tyler pavay"))
            try screen.photograph(named: "champion-own-profile-two-titles")
        }
    }

    @Test
    func theComparisonNamesEachTitleUnderTheName() async throws {
        let viewer = CrossUserIdentityResolver.resolve(
            userId: "viewer",
            displayName: "Tyler Pavay",
            photoURL: nil,
            isCurrentUser: true,
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        let registry = registry()
        for (userId, name, expected) in [
            ("fixture-zoe", "Zoe Ramirez", "week 38 champion"),
            ("double", "Ezra Kim", "august & week 38 champion")
        ] {
            let other = CrossUserIdentityResolver.resolve(
                userId: userId,
                displayName: name,
                photoURL: nil,
                isCurrentUser: false,
                blockedUserIds: [],
                isBlockListHydrated: true
            )
            let size = CGSize(width: 402, height: 240)
            try await RenderedScreen.host(
                ProfileComparisonHeader(
                    viewerIdentity: viewer,
                    otherIdentity: other,
                    isViewerLoading: false,
                    isOtherLoading: false
                )
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(registry)
                .environment(\.colorScheme, .dark),
                size: size
            ) { screen in
                let copy = try await screen.copy()
                #expect(copy.contains(expected), "\(copy)")
                try screen.photograph(named: "champion-comparison-\(userId)")
            }
        }
    }

    @Test
    func theLiveRaceRowWearsTheCompactCrown() async throws {
        let rows = [
            ("fixture-noah", "Noah Grant", 13, 1_688, false),
            ("fixture-zoe", "Zoe Ramirez", 14, 1_637, false),
            ("viewer", "Tyler Pavay", 15, 1_542, true)
        ].map { userId, name, rank, steps, isCurrentUser in
            CrossUserIdentityAdapter.replayRow(
                LiveReplayLeaderboardRow(
                    id: userId,
                    rank: rank,
                    displayName: name,
                    avatarToken: "",
                    photoURL: nil,
                    stepsAtBucket: steps,
                    finalSteps: steps,
                    deltaFromUser: 0,
                    isCurrentUser: isCurrentUser,
                    isPersonalBest: false,
                    completionDurationSeconds: nil,
                    userId: userId,
                    gender: nil,
                    age: nil,
                    locationCity: nil
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
        let size = CGSize(width: 402, height: 360)
        try await RenderedScreen.host(
            LiveReplayLeaderboardPanel(
                rows: rows,
                progressScaleSteps: 2_000,
                targetStepGoal: nil,
                progress: 0.77,
                currentUserPhotoURL: nil,
                fetchFailed: false,
                tint: .accent,
                effectiveColorScheme: .dark,
                showsFilter: false
            )
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(registry())
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            #expect(try await screen.copy().contains("zoe ramirez"))
            try screen.photograph(named: "champion-live-race-row")
        }
    }

    @Test
    func theSettingsHeaderWearsTheFullCrown() async throws {
        let size = CGSize(width: 402, height: 280)
        try await RenderedScreen.host(
            ProfileHeaderView(userId: "fixture-zoe", photoURL: nil, displayName: "Zoe Ramirez", email: "zoe@example.com")
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(registry())
                .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            #expect(try await screen.copy().contains("zoe ramirez"))
            try screen.photograph(named: "champion-settings-header")
        }
    }

    @Test
    func theChampionStripLeadsTheStepsBoardAndTheWindowLineCountsDown() async throws {
        let results = FakeLeaderboardResults()
        results.store(fixtures.weekBundle(period: fixtures.periods().week, viewerPlaces: false, viewerWins: false))
        let registry = registry(repository: results)
        await registry.refresh()
        #expect(registry.reign(for: .weekly) != nil)
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, LeaderboardStats.self)

        let size = CGSize(width: 402, height: 620)
        try await RenderedScreen.host(
            NavigationStack {
                LeaderboardView(initialTimeFrame: .weekly, viewSource: .tab)
            }
            .environment(AuthenticationViewModel())
            .environment(await hydratedModerationStore())
            .environment(NetworkConnectivityService.shared)
            .environment(TabRouter())
            .environment(registry)
            .modelContainer(container)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("week 38 champion"), "no champion strip: \(copy)")
            #expect(copy.contains("zoe ramirez · 8,836 steps"), "\(copy)")
            #expect(copy.contains("ends "), "no countdown on the window line: \(copy)")
            try screen.photograph(named: "champion-strip-weekly-board")
        }
    }

    @Test
    func pastChampionsShowsTheBoardFrozenAtItsFinalResult() async throws {
        let results = FakeLeaderboardResults()
        var period = fixtures.periods().week
        for index in 0..<2 {
            results.store(fixtures.weekBundle(period: period, viewerWins: false, tie: index == 1))
            period = period.previous!
        }
        let viewModel = PastChampionsViewModel(timeFrame: .weekly, repository: results, now: { Self.now })
        let size = CGSize(width: 402, height: 760)
        try await RenderedScreen.host(
            NavigationStack {
                PastChampionsView(viewModel: viewModel)
            }
            .environment(AuthenticationViewModel())
            .environment(await hydratedModerationStore())
            .environment(registry())
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            size: size,
            settle: .until(turns: 120) { _ in viewModel.state == .loaded }
        ) { screen in
            try await screen.settle()
            let copy = try await screen.copy()
            #expect(copy.contains("week 38"), "\(copy)")
            #expect(copy.contains("38 climbers · most climbs: ezra kim (9)"), "\(copy)")
            try screen.photograph(named: "champion-past-board-week")
        }
    }

    // MARK: - Helpers

    private func avatar(_ userId: String, _ size: CGFloat, label: String) -> some View {
        VStack(spacing: 10) {
            ClimberAvatar(
                userId: userId,
                photoURL: nil,
                placeholder: .initials(
                    ChampionRecapFixtures.names.first { $0.id == userId }.map { PublicClimberIdentity.avatarToken(for: $0.name) } ?? "TP",
                    fill: Color(hex: "3A3A3C"),
                    foreground: .white
                ),
                size: size
            )
            Text(label)
                .font(.montserratMedium(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private struct Ink {
        let inPerch: Int
    }

    /// Hosts one grey picture on black and counts every saturated pixel: the only coloured
    /// ink on that canvas is the crown.
    private func crownInk(
        userId: String?,
        size: CGFloat,
        registry: ChampionRegistry,
        showsMark: Bool = true,
        placeholder: ClimberAvatarPlaceholder = .initials("ZR", fill: Color(hex: "3A3A3C"), foreground: .white)
    ) async throws -> Ink {
        let canvas = CGSize(width: size * 2.4, height: size * 2.4)
        return try await RenderedScreen.host(
            ClimberAvatar(
                userId: userId,
                photoURL: nil,
                placeholder: placeholder,
                size: size,
                showsChampionMark: showsMark
            )
            .frame(width: canvas.width, height: canvas.height)
            .background(Color.black)
            .environment(registry)
            .environment(\.colorScheme, .dark),
            size: canvas
        ) { screen in
            try screen.withPixels(scale: 2) { pixels in
                let count = pixels.count(in: CGRect(origin: .zero, size: canvas)) { pixel in
                    let high = Int(max(pixel.red, pixel.green, pixel.blue))
                    let low = Int(min(pixel.red, pixel.green, pixel.blue))
                    return high - low > 60 && high > 90
                }
                return Ink(inPerch: count)
            }
        }
    }

    private static func snapshot(userId: String) -> ProfileSnapshot {
        ProfileSnapshot(
            demographics: ProfileDemographicsSnapshot(userId: userId),
            stats: ProfileStatsSnapshot(
                totalClimbsCompleted: 0,
                totalFirstAscents: 0,
                achievementCounts: .zero,
                mostCompletedClimbId: nil,
                currentStreakWeeks: 0,
                bestStreakWeeks: 0,
                prMostSteps: 0,
                prLongestClimbSeconds: 0,
                prHighestSPM: 0,
                lifetimeTotalSteps: 0,
                lifetimeDurationSeconds: 0,
                totalClimbs: 0,
                averageStepsPerMinute: 0
            ),
            standings: [],
            activityWorkouts: [],
            collection: ProfileCollectionSummary(
                collectedCount: 0,
                catalogCount: 0,
                previewCards: [],
                launchedCards: [],
                comingSoonClimbs: []
            ),
            achievements: .empty,
            firstAscentsHeld: [],
            openFirstAscents: [],
            records: ProfileRecordSummary(personalRecords: [], featuredBestEffort: nil),
            trends: ProfileTrendSummary(currentSteps: 0, previousSteps: 0, daysWithData: 0),
            recentWorkouts: []
        )
    }

    private func hydratedModerationStore() async -> ModerationStore {
        let store = ModerationStore(repository: NoBlocksModerationRepository())
        await store.hydrate(for: "viewer")
        return store
    }
}
