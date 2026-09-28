import Foundation
import Testing
@testable import AscendApp

/// The champion vocabulary: which title leads, where the crown perches, how a board counts
/// down, and how a frozen result and its placings are read back.
struct ChampionModelTests {
    private static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Titles

    @Test
    func theRarestTitleLeadsAndTheOthersBecomeDots() {
        let titles = ChampionTitles([.weekly, .yearly, .monthly])
        #expect(titles.leading == .yearly)
        #expect(titles.others == [.monthly, .weekly])
        #expect(!titles.isUndisputed)

        let every = ChampionTitles(Set(ChampionTitle.allCases))
        #expect(every.leading == .allTime)
        #expect(every.others == [.yearly, .monthly, .weekly])
        #expect(every.isUndisputed)

        let two = ChampionTitles([.weekly, .monthly])
        #expect(two.leading == .monthly)
        #expect(two.others == [.weekly])
        #expect(!two.isUndisputed)

        #expect(ChampionTitles.none.leading == nil)
        #expect(ChampionTitles.none.others.isEmpty)
    }

    @Test
    func everyStepsBoardButTodayAwardsATitle() {
        #expect(ChampionTitle(timeFrame: .weekly) == .weekly)
        #expect(ChampionTitle(timeFrame: .monthly) == .monthly)
        #expect(ChampionTitle(timeFrame: .yearly) == .yearly)
        #expect(ChampionTitle(timeFrame: .allTime) == .allTime)
        #expect(ChampionTitle(timeFrame: .daily) == nil)
        #expect(ChampionTitle.allTime.isFinalized == false)
        #expect(ChampionTitle.yearly.isFinalized)
        #expect(ChampionTitle.weekly.crownAssetName == "LeaderboardCrown")
        #expect(ChampionTitle.monthly.crownAssetName == "LeaderboardCrownDiamond")
        #expect(ChampionTitle.yearly.crownAssetName == "LeaderboardCrownRuby")
        #expect(ChampionTitle.allTime.crownAssetName == "LeaderboardCrownMythic")
    }

    // MARK: - The perch

    @Test
    func largePicturesWearTheFullPerchAndRowsTheCompactOne() {
        let hero = ChampionCrownPerch(avatarSize: 88)
        #expect(hero.isFull)
        #expect(abs(hero.crownWidth - 88 * 0.58) < 0.001)
        #expect(hero.rotationDegrees == 22)
        #expect(hero.showsTitleDots)
        // Right edge 0.17 of the picture past its edge; top 0.31 above it.
        #expect(abs((hero.crownCenter.x + hero.crownWidth / 2) - 88 * 1.17) < 0.001)
        #expect(abs((hero.crownCenter.y - hero.crownHeight / 2) - -88 * 0.31) < 0.001)

        let row = ChampionCrownPerch(avatarSize: 44)
        #expect(!row.isFull)
        #expect(abs(row.crownWidth - 22) < 0.001)
        #expect(row.rotationDegrees == 20)
        #expect(!row.showsTitleDots)
        // The compact perch rises no more than a fifth of the picture, so it stays in a row's padding.
        #expect(row.crownCenter.y - row.crownHeight / 2 >= -44 * 0.2 - 0.001)

        #expect(ChampionCrownPerch(avatarSize: 56).isFull)
        #expect(!ChampionCrownPerch(avatarSize: 55.9).isFull)
    }

    // MARK: - Countdown

    @Test
    func aBoardCountsDownInDaysAndHoursThenHoursAndMinutes() throws {
        let week = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: Self.utc(2026, 9, 24, 12))
        // Ends Monday Sep 28 00:00 UTC.
        let thursday = try #require(LeaderboardCountdown.make(period: week, now: Self.utc(2026, 9, 25, 10)))
        #expect(thursday.text == "ENDS IN 2D 14H")
        #expect(!thursday.isLastDay)

        let lastDay = try #require(LeaderboardCountdown.make(period: week, now: Self.utc(2026, 9, 27, 19, 48)))
        #expect(lastDay.text == "ENDS IN 4H 12M")
        #expect(lastDay.remainingText == "4H 12M LEFT")
        #expect(lastDay.isLastDay)

        let lastHour = try #require(LeaderboardCountdown.make(period: week, now: Self.utc(2026, 9, 27, 23, 22)))
        #expect(lastHour.text == "ENDS IN 38M")

        #expect(LeaderboardCountdown.make(period: week, now: Self.utc(2026, 9, 28)) == nil)
    }

    @Test
    func theYearlyBoardCountsInDaysAndAllTimeNeverEnds() throws {
        let year = LeaderboardTimeFrame.yearly.currentPeriod(referenceDate: Self.utc(2026, 9, 27))
        let countdown = try #require(LeaderboardCountdown.make(period: year, now: Self.utc(2026, 9, 27, 12)))
        #expect(countdown.text == "ENDS IN 95D")

        let allTime = LeaderboardTimeFrame.allTime.currentPeriod(referenceDate: Self.utc(2026, 9, 27))
        #expect(LeaderboardCountdown.make(period: allTime, now: Self.utc(2026, 9, 27)) == nil)
    }

    // MARK: - Periods

    @Test
    func theReigningPeriodIsTheOneThatClosedMostRecently() throws {
        let now = Self.utc(2026, 9, 27, 21)
        let week = try #require(LeaderboardTimeFrame.weekly.previousPeriod(referenceDate: now))
        #expect(week.key == "2026-W38")
        #expect(week.next?.key == "2026-W39")
        #expect(week.previous?.key == "2026-W37")

        let month = try #require(LeaderboardTimeFrame.monthly.previousPeriod(referenceDate: now))
        #expect(month.key == "2026-M08")
        #expect(try #require(LeaderboardTimeFrame.yearly.previousPeriod(referenceDate: now)).key == "2025")
        #expect(LeaderboardTimeFrame.allTime.previousPeriod(referenceDate: now) == nil)

        // Week 1 opens in the previous calendar year and still carries the next year's key.
        let januaryFirstWeek = try #require(LeaderboardTimeFrame.weekly.previousPeriod(referenceDate: Self.utc(2026, 1, 6)))
        #expect(januaryFirstWeek.key == "2026-W01")
    }

    @Test
    func aTitleIsNamedByThePeriodItWasWonIn() throws {
        let now = Self.utc(2026, 9, 27)
        let week = try #require(LeaderboardTimeFrame.weekly.previousPeriod(referenceDate: now))
        let month = try #require(LeaderboardTimeFrame.monthly.previousPeriod(referenceDate: now))
        let year = try #require(LeaderboardTimeFrame.yearly.previousPeriod(referenceDate: now))
        #expect(ChampionTitleLine.periodName(for: week) == "WEEK 38")
        #expect(ChampionTitleLine.periodName(for: month) == "AUGUST")
        #expect(ChampionTitleLine.periodName(for: year) == "2025")
    }

    @Test
    func severalTitlesNameTheRarestFirstAndAllThreeIsUndisputed() throws {
        let now = Self.utc(2026, 9, 27)
        let fixtures = ChampionRecapFixtures(viewerId: "me", now: now)
        let reigns = fixtures.reigns(crowning: [.weekly, .monthly])
        let line = try #require(ChampionTitleLine.make(titles: ChampionTitles([.weekly, .monthly]), reigns: reigns))
        #expect(line.text == "LAST MONTH'S & LAST WEEK'S CHAMPION")
        #expect(line.leadingTitle == .monthly)

        let undisputed = try #require(ChampionTitleLine.make(
            titles: ChampionTitles(Set(ChampionTitle.allCases)),
            reigns: fixtures.reigns(crowning: Set(ChampionTitle.allCases))
        ))
        #expect(undisputed.text == "UNDISPUTED CHAMPION")
        #expect(undisputed.leadingTitle == .allTime)

        let allTime = try #require(ChampionTitleLine.make(
            titles: ChampionTitles([.allTime, .weekly]),
            reigns: fixtures.reigns(crowning: [.allTime, .weekly])
        ))
        #expect(allTime.text == "ALL-TIME & LAST WEEK'S CHAMPION")

        // An exact tie on every held title is a co-championship.
        let week = fixtures.periods().week
        let tied = [ChampionTitle.weekly: ChampionReign(
            title: .weekly,
            result: LeaderboardResult(
                period: week,
                climberCount: 12,
                championUserIds: ["a", "b"],
                podiumUserIds: ["a", "b"],
                mostClimbs: nil,
                community: .empty
            ),
            champions: []
        )]
        let coChampion = try #require(ChampionTitleLine.make(titles: ChampionTitles([.weekly]), reigns: tied))
        #expect(coChampion.text == "LAST WEEK'S CO-CHAMPION")
    }

    // MARK: - Parsing a result

    @Test
    func aResultParsesItsChampionsCommunityAndMostClimbs() throws {
        let data: [String: Any] = [
            "schemaVersion": 1,
            "timeFrame": "weekly",
            "periodKey": "2026-W38",
            "periodStartAt": Self.utc(2026, 9, 14),
            "periodEndAt": Self.utc(2026, 9, 21),
            "metric": "steps",
            "climberCount": 9,
            "championUserIds": ["zoe", "noah"],
            "podiumUserIds": ["zoe", "noah", "maya"],
            "mostClimbs": ["count": 9, "userIds": ["ezra"]],
            "community": ["climbers": 9, "climbs": 41, "steps": 12_000, "floors": 600]
        ]
        let result = try #require(LeaderboardResultParser.result(from: data))
        #expect(result.id == "weekly_2026-W38")
        #expect(result.title == .weekly)
        #expect(result.championUserIds == ["zoe", "noah"])
        #expect(result.mostClimbs == .init(count: 9, userIds: ["ezra"]))
        #expect(result.community.climbs == 41)

        var allTime = data
        allTime["timeFrame"] = "all_time"
        #expect(LeaderboardResultParser.result(from: allTime) == nil)
    }

    @Test
    func aPlacingOnlyShowsAPublishedIdentity() throws {
        let published: [String: Any] = [
            "userId": "zoe",
            "rank": 1,
            "totalSteps": 836,
            "totalWorkouts": 2,
            "displayName": "Zoe Ramirez",
            "photoURL": "",
            "identityPolicyVersion": PublicClimberIdentity.policyVersion,
            "identityState": "published",
            "identityChangedAt": Self.utc(2026, 9, 1)
        ]
        let placing = try #require(LeaderboardResultParser.placing(from: published))
        #expect(placing.entry(isCurrentUser: false, isTied: false).formattedValue == "836")

        var deleted = published
        deleted["identityState"] = "deleted"
        deleted["displayName"] = "Anonymous Climber"
        let anonymous = try #require(LeaderboardResultParser.placing(from: deleted))
        let moderated = CrossUserIdentityAdapter.leaderboardEntry(
            anonymous.entry(isCurrentUser: false, isTied: false),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        #expect(moderated.identity.displayName == PublicClimberIdentity.anonymousDisplayName)

        var pending = published
        pending["identityState"] = "pending_public_profile"
        let hidden = try #require(LeaderboardResultParser.placing(from: pending))
        let pendingEntry = CrossUserIdentityAdapter.leaderboardEntry(
            hidden.entry(isCurrentUser: false, isTied: false),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
        #expect(pendingEntry.identity.displayName != "Zoe Ramirez")

        var noRank = published
        noRank["rank"] = 0
        #expect(LeaderboardResultParser.placing(from: noRank) == nil)
    }

    @Test
    func placingsSharingARankReadAsATie() {
        let placings = [
            LeaderboardPlacing(userId: "a", unresolvedIdentity: .init(displayName: "A", photoURL: nil), rank: 1, totalSteps: 10, totalWorkouts: 1),
            LeaderboardPlacing(userId: "b", unresolvedIdentity: .init(displayName: "B", photoURL: nil), rank: 1, totalSteps: 10, totalWorkouts: 1),
            LeaderboardPlacing(userId: "c", unresolvedIdentity: .init(displayName: "C", photoURL: nil), rank: 3, totalSteps: 5, totalWorkouts: 1)
        ]
        let entries = placings.entries(currentUserId: "c")
        #expect(entries.map(\.isTied) == [true, true, false])
        #expect(entries.map(\.isCurrentUser) == [false, false, true])
    }

    @Test
    func theStripNamesTheReignRelativeToNow() {
        #expect(ChampionStripView.label(for: .weekly, championCount: 1) == "LAST WEEK'S CHAMPION")
        #expect(ChampionStripView.label(for: .monthly, championCount: 1) == "LAST MONTH'S CHAMPION")
        #expect(ChampionStripView.label(for: .yearly, championCount: 1) == "LAST YEAR'S CHAMPION")
        #expect(ChampionStripView.label(for: .weekly, championCount: 2) == "LAST WEEK'S CHAMPIONS")
    }

    @Test
    func championNamesJoinTwoAndCountTheRest() {
        #expect(ChampionNames.joined(["Zoe R."]) == "Zoe R.")
        #expect(ChampionNames.joined(["Zoe R.", "Noah G."]) == "Zoe R. & Noah G.")
        #expect(ChampionNames.joined(["Zoe R.", "Noah G.", "Ezra K."]) == "Zoe R. + 2")
    }
}
