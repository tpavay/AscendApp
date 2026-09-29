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
        #expect(catchUp.weeksAway == 3)
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
    func aLongAbsenceCountsItsRealWeeksAndAClimbedWeekShowsTheClimbersOwnResult() throws {
        var period = fixtures.periods().week
        let away = PeriodRecap(
            id: "weekly_\(period.key)",
            period: period,
            variant: .inactive,
            active: nil,
            inactive: PeriodRecap.Inactive(gapCount: 16, lastClimbAt: nil, suggestedClimbId: nil, suggestedClimbName: nil),
            seenAt: nil
        )
        var recaps = [away]
        var results: [String: PeriodRecapResultBundle] = [away.resultID: fixtures.weekBundle(period: period, viewerPlaces: false, viewerWins: false)]
        period = period.previous!
        let climbed = fixtures.recap(
            period: period,
            variant: .active,
            active: fixtures.active(rank: 4, climbers: 38, steps: 7_904, climbs: 5, awardRank: 4)
        )
        recaps.append(climbed)
        results[climbed.resultID] = fixtures.weekBundle(period: period, viewerPlaces: false, viewerWins: false)
        for _ in 0..<5 {
            period = period.previous!
            recaps.append(fixtures.recap(period: period, variant: .inactive))
        }

        let story = try #require(PeriodRecapStoryBuilder.build(recaps: recaps, results: results, viewerId: "me", now: Self.now))
        guard case .catchUp(let catchUp) = story.pages.first else {
            Issue.record("no catch-up page")
            return
        }
        #expect(catchUp.weeksAway == 16)
        #expect(PeriodRecapCopy.catchUpHeadline(weeks: catchUp.weeksAway, champions: 2) == "Sixteen weeks. Two champions.")
        let climbedLine = try #require(catchUp.lines.first { $0.period.key == climbed.period.key })
        #expect(climbedLine.yours?.steps == 7_904)
        #expect(PeriodRecapCopy.catchUpYoursLine(try #require(climbedLine.yours)) == "You: #4 · 7,904 steps")
        #expect(story.recapIDs.count == recaps.count)
        #expect(story.oldestPeriodEndAt == period.endAt)
    }

    @Test
    func everyEndingOfAFirstClimbInvitationIsTheFirstClimb() throws {
        let (week, month) = fixtures.periods()
        let weekRecap = fixtures.recap(period: week, variant: .neverClimbed)
        let monthRecap = fixtures.recap(period: month, variant: .neverClimbed)
        let olderWeek = fixtures.recap(period: week.previous!, variant: .neverClimbed)
        let results = [
            weekRecap.resultID: fixtures.weekBundle(period: week, viewerPlaces: false, viewerWins: false),
            monthRecap.resultID: fixtures.monthBundle(period: month)
        ]

        for recaps in [[weekRecap], [weekRecap, monthRecap], [weekRecap, olderWeek]] {
            let story = try #require(PeriodRecapStoryBuilder.build(recaps: recaps, results: results, viewerId: "me", now: Self.now))
            #expect(story.isFirstClimbInvitation)
            let ending = story.ending(on: try #require(story.pages.last))
            #expect(ending.title == "START YOUR FIRST CLIMB", "\(kinds(story))")
            #expect(ending.exit == .startClimb)
        }

        let climber = try #require(fixtures.story(.catchUp))
        #expect(climber.ending(on: try #require(climber.pages.last)).title == "CLIMB TODAY")
    }

    @Test
    func onlyThePeriodsTheStoryShowsAreRead() {
        let (week, month) = fixtures.periods()
        let recaps = [
            fixtures.recap(period: week, variant: .active, active: fixtures.active(rank: 3, climbers: 38, steps: 100, climbs: 1, awardRank: nil)),
            fixtures.recap(period: week.previous!, variant: .inactive),
            fixtures.recap(period: month, variant: .active, active: fixtures.active(rank: 3, climbers: 38, steps: 100, climbs: 1, awardRank: nil)),
            fixtures.recap(period: month.previous!, variant: .inactive)
        ]
        #expect(PeriodRecapStoryBuilder.resultIDs(for: recaps) == ["weekly_\(week.key)", "monthly_\(month.key)"])
    }

    @Test
    func aMonthlyReignNamesTheDateItEnds() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US")
        let month = fixtures.periods().month
        let monthLine = PeriodRecapCopy.reignLine(endsAt: month.next?.endAt, now: Self.now, timeZone: utc, locale: locale)
        #expect(monthLine?.contains("October 1") == true, "\(monthLine ?? "")")
        let week = fixtures.periods().week
        let weekLine = PeriodRecapCopy.reignLine(endsAt: week.next?.endAt, now: Self.now, timeZone: utc, locale: locale)
        #expect(weekLine?.contains("September") == false, "\(weekLine ?? "")")
    }

    @Test
    func everyFirstAscentIsItsOwnRowAndAnUnnamedOneIsStillShown() {
        let week = fixtures.periods().week
        let active = PeriodRecap.Active(
            rank: 3,
            climberCount: 38,
            percentileBand: nil,
            climbs: 4,
            steps: 7_000,
            floors: 350,
            previousClimbs: nil,
            previousSteps: nil,
            awardRank: 3,
            firstAscents: [
                PeriodRecap.FirstAscent(climbId: "tallinn", name: "Tallinn TV Tower"),
                PeriodRecap.FirstAscent(climbId: "cn-tower", name: nil),
                PeriodRecap.FirstAscent(climbId: "unknown", name: nil)
            ],
            landmarksFinished: []
        )
        let rows = PeriodRecapCopy.earnedRows(for: active, period: week) { $0 == "cn-tower" ? "CN Tower" : nil }
        #expect(rows.count == 4)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.detail) == [
            "Bronze on the weekly board",
            "Tallinn TV Tower - first to finish it",
            "CN Tower - first to finish it",
            "First to finish it"
        ])
    }

    @Test
    func awardsAreNamedInWords() {
        let week = fixtures.periods().week
        #expect(PeriodRecapCopy.award(rank: 1, period: week).title == "Champion")
        #expect(PeriodRecapCopy.award(rank: 7, period: week).detail == "#7 on the weekly board")
        #expect(PeriodRecapCopy.award(rank: 42, period: week).title == "Top 100 finish")
    }
}
