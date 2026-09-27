import Foundation
import Testing
@testable import AscendApp

/// What the recap shows, decided once from the unseen recaps and the frozen results.
struct PeriodRecapStoryBuilderTests {
    /// Sunday 2026-09-27, 21:00 UTC: week 38 and August are the latest closed periods.
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: 21)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private let fixtures = ChampionRecapFixtures(viewerId: "me", viewerName: "Tyler Pavay", now: Self.now)

    private func kinds(_ story: PeriodRecapStory) -> [String] {
        story.pages.map { page in
            switch page {
            case .everyone: "everyone"
            case .yours: "yours"
            case .noClimbs: "noClimbs"
            case .crown: "crown"
            case .crowns: "crowns"
            case .catchUp: "catchUp"
            }
        }
    }

    @Test
    func aWeekIsEveryoneThenYoursThenTheCrown() throws {
        let story = try #require(fixtures.story(.week))
        #expect(kinds(story) == ["everyone", "yours", "crown"])
        #expect(story.chapters.isEmpty)
        #expect(story.recapIDs == ["weekly_2026-W38"])

        guard case .crown(let crown) = story.pages[2] else {
            Issue.record("the story does not end on the crown")
            return
        }
        #expect(!crown.viewerIsChampion)
        #expect(crown.title == .weekly)
        #expect(crown.runnersUp.map(\.rank) == [2, 3])
        #expect(crown.mostClimbsCount == 9)

        guard case .yours(let personal) = story.pages[1] else {
            Issue.record("the second page is not the climber's own week")
            return
        }
        #expect(personal.bestEfforts.count == 2)
        #expect(personal.recap.awardRank == 3)
    }

    @Test
    func theWinnersLastPageIsTheirCoronation() throws {
        let story = try #require(fixtures.story(.coronation))
        guard case .crown(let crown) = story.pages.last else {
            Issue.record("the coronation is not the last page")
            return
        }
        #expect(crown.viewerIsChampion)
        #expect(PeriodRecapCopy.crownHeadline(names: ["Tyler Pavay"], viewerIsChampion: true) == "You took the crown.")
    }

    @Test
    func anExactTieCrownsBothClimbers() throws {
        let story = try #require(fixtures.story(.coChampions))
        guard case .crown(let crown) = story.pages.last else {
            Issue.record("the story does not end on the crown")
            return
        }
        #expect(crown.isTie)
        #expect(crown.champions.count == 2)
        #expect(PeriodRecapCopy.crownDetail(steps: 1_776, climberCount: 38, isTie: true) == "Tied at exactly 1,776 steps · 38 climbers")
    }

    @Test
    func aWeekAndAMonthClosingTogetherShowTheMonthFirstAndEndOnBothCrowns() throws {
        let story = try #require(fixtures.story(.weekAndMonth))
        #expect(kinds(story) == ["everyone", "yours", "everyone", "yours", "crowns"])
        #expect(story.chapters.map(\.label) == ["AUGUST", "WEEK 38"])
        #expect(story.chapters.map(\.pageRange) == [0..<2, 2..<5])

        guard case .crowns(let crowns) = story.pages.last else {
            Issue.record("the story does not end on both crowns")
            return
        }
        #expect(crowns.map(\.title) == [.monthly, .weekly])
    }

    @Test
    func weeksAwayFoldIntoOneCatchUpPage() throws {
        let story = try #require(fixtures.story(.catchUp))
        #expect(kinds(story) == ["catchUp"])
        #expect(story.recapIDs.count == 4)

        guard case .catchUp(let catchUp) = story.pages[0] else {
            Issue.record("no catch-up page")
            return
        }
        #expect(catchUp.missedWeeks == 3)
        #expect(catchUp.lines.count == 4)
        // Only the title still held wears its crown.
        #expect(catchUp.lines.filter(\.isReigning).count == 2)
        #expect(PeriodRecapCopy.catchUpHeadline(weeks: 3, champions: 3) == "Three weeks. Three champions.")
    }

    @Test
    func aWeekWithoutClimbsIsOneShortPage() throws {
        let story = try #require(fixtures.story(.noClimbs))
        #expect(kinds(story) == ["noClimbs"])
        guard case .noClimbs(let summary) = story.pages[0] else { return }
        #expect(summary.crown != nil)
        #expect(summary.community.climbs == 214)
    }

    @Test
    func someoneWhoNeverClimbedSeesEveryoneAndTheCrownThenTheirFirstClimb() throws {
        let story = try #require(fixtures.story(.neverClimbed))
        #expect(kinds(story) == ["everyone", "crown"])
        #expect(story.isFirstClimbInvitation)
    }

    @Test
    func aRecapAlreadySeenOrNotYetClosedIsNeverShown() {
        let week = fixtures.periods().week
        let seen = PeriodRecap(
            id: "weekly_\(week.key)",
            period: week,
            variant: .active,
            active: fixtures.active(rank: 3, climbers: 38, steps: 100, climbs: 1, awardRank: nil),
            inactive: nil,
            seenAt: Self.now
        )
        #expect(PeriodRecapStoryBuilder.build(recaps: [seen], results: [:], viewerId: "me", now: Self.now) == nil)

        let current = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: Self.now)
        let open = PeriodRecap(
            id: "weekly_\(current.key)",
            period: current,
            variant: .active,
            active: fixtures.active(rank: 3, climbers: 38, steps: 100, climbs: 1, awardRank: nil),
            inactive: nil,
            seenAt: nil
        )
        #expect(PeriodRecapStoryBuilder.build(recaps: [open], results: [:], viewerId: "me", now: Self.now) == nil)
    }

    @Test
    func theResultsAStoryNeedsAreTheNewestFourWeeksAndTwoMonths() {
        var period = fixtures.periods().week
        var recaps: [PeriodRecap] = []
        for _ in 0..<6 {
            recaps.append(fixtures.recap(period: period, variant: .inactive))
            period = period.previous!
        }
        let month = fixtures.periods().month
        recaps.append(fixtures.recap(period: month, variant: .inactive))
        recaps.append(fixtures.recap(period: month.previous!, variant: .inactive))
        recaps.append(fixtures.recap(period: month.previous!.previous!, variant: .inactive))

        let ids = PeriodRecapStoryBuilder.resultIDs(for: recaps)
        #expect(ids.filter { $0.hasPrefix("weekly_") }.count == 4)
        #expect(ids.filter { $0.hasPrefix("monthly_") } == ["monthly_2026-M08", "monthly_2026-M07"])
    }

    // MARK: - Copy

    @Test
    func periodLabelsAreUTCPinnedAndCompact() {
        let (week, month) = fixtures.periods()
        #expect(PeriodRecapCopy.periodLabel(for: week) == "WEEK 38 · SEP 14-20, 2026")
        #expect(PeriodRecapCopy.periodLabel(for: month) == "AUGUST 2026")
        let straddling = LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: week.startAt.addingTimeInterval(-14 * 86_400))
        #expect(PeriodRecapCopy.compactWindow(for: straddling) == "AUG 31-SEP 6")
    }

    @Test
    func gainsAreOnlyEverUpward() {
        let week = fixtures.periods().week
        #expect(PeriodRecapCopy.gainLine(current: 5, previous: 3, period: week) == "+2 on last week")
        #expect(PeriodRecapCopy.gainLine(current: 3, previous: 5, period: week) == nil)
        #expect(PeriodRecapCopy.gainLine(current: 3, previous: nil, period: week) == nil)
        let month = fixtures.periods().month
        #expect(PeriodRecapCopy.gainLine(current: 18, previous: 12, period: month) == "+6 on July")
    }

    @Test
    func awardsAreNamedInWords() {
        let week = fixtures.periods().week
        #expect(PeriodRecapCopy.award(rank: 1, period: week).title == "Champion")
        #expect(PeriodRecapCopy.award(rank: 7, period: week).detail == "#7 on the weekly board")
        #expect(PeriodRecapCopy.award(rank: 42, period: week).title == "Top 100 finish")
    }
}
