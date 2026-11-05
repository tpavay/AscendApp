import Foundation
import Testing
@testable import AscendApp

/// What the selling screens (01 to 05) decide apart from drawing: the copy contract, the record
/// cards' numbers, which gear 04 shows in which month, and what Reduce Motion takes away.
@MainActor
struct OnboardingV3SellScreensTests {
    // MARK: - Copy contract

    /// The wording rules the captain set for onboarding: no "race", no "live", no "field", no em
    /// dash. Whole words only - "deliver" is not "live".
    @Test
    func noSellingScreenSaysRaceLiveOrFieldOrUsesAnEmDash() {
        let banned = try! Regex(#"\b(race|races|racing|raced|live|lives|field|fields)\b"#).ignoresCase()

        for line in SellScreenCopy.all {
            #expect(line.firstMatch(of: banned) == nil, "banned word in: \(line)")
            #expect(!line.contains("\u{2014}"), "em dash in: \(line)")
        }
    }

    @Test
    func nothingIsFramedAgainstAnotherApp() {
        let competitors = ["peloton", "strava", "stairmaster", "zwift", "other apps", "other stair stepper apps"]

        for line in SellScreenCopy.all {
            for name in competitors {
                #expect(!line.lowercased().contains(name), "\(name) in: \(line)")
            }
        }
    }

    @Test
    func theHeadphonesLineDropsLive() {
        let headphones = SellScreenCopy.CountMethods.methods[0]

        #expect(headphones.detail == "AirPods or Beats count every step, and other climbers move up beside you.")
        #expect(headphones.isBest)
        #expect(SellScreenCopy.CountMethods.methods.filter(\.isBest).count == 1)
    }

    // MARK: - Record cards

    @Test
    func theFourRecordCardsCarryTheSpecsNumbers() {
        let cards = SellRecordCard.examples

        #expect(cards.map(\.kicker) == ["ALL-TIME BEST", "ALL-TIME BEST", "2ND ALL-TIME", "2ND ALL-TIME"])
        #expect(cards.map(\.title) == [
            "Most Steps in 60 Min", "Fastest 3,000 Steps", "Most Steps in 60 Min", "Fastest 2,000 Steps"
        ])
        #expect(cards.map { $0.detail() } == [
            "7,309 steps · Oct 3", "40:08 · Oct 5", "5,004 steps · Oct 9", "24:33 · Sep 29"
        ])
    }

    @Test
    func goldCardsAreRankOneAndSilverRankTwo() {
        #expect(SellRecordCard.examples.map(\.tier.rank) == [1, 1, 2, 2])
    }

    // MARK: - Gear

    private func catalog() -> UnlockCatalog {
        HostedUnlockCatalogRepository.bundledCatalog()
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Thanksgiving has six items and three are its showcase, so the three others are all drawn and
    /// the showcase's first fills the fourth place.
    @Test
    func aSixItemEventFillsItsFourPiecesFromTheShowcase() throws {
        let catalog = catalog()
        let event = try #require(SellGearSelection.event(in: catalog, today: day(2_026, 11, 4)))
        let selection = try #require(SellGearSelection(catalog: catalog, today: day(2_026, 11, 4)))

        #expect(event.id == "thanksgiving-2026")
        #expect(catalog.items(earnedIn: event).count == 6)
        #expect(selection.centerpiece.item.id == "golden_turkey")
        #expect(selection.companions.map(\.item.id) == ["cornucopia", "turkey_giant", "harvest_gourd"])
        #expect(selection.pieces.map(\.requirement) == ["25K STEPS", "5 CLIMBS", "50K STEPS", "OPEN ASCEND"])
        #expect(Set(selection.pieces.map(\.item)).intersection(catalog.showcase(of: event)).count == 1)
    }

    @Test
    func octoberShowsHalloweenGearThatIsNotInItsShowcase() throws {
        let catalog = catalog()
        let event = try #require(catalog.event(id: "halloween-2026"))
        let selection = try #require(SellGearSelection(catalog: catalog, today: day(2_026, 10, 15)))

        #expect(selection.pieces.allSatisfy { $0.item.earn.event == event.id })
        #expect(selection.centerpiece.item.shape == .pumpkinMidnight)
        #expect(selection.centerpiece.requirement == "25K STEPS")
        #expect(selection.companions.map(\.requirement) == ["1 CLIMB", "5 CLIMBS", "15 CLIMBS"])
        #expect(Set(selection.pieces.map(\.id)).count == 4, "no piece twice")
        #expect(Set(selection.pieces.map(\.item)).isDisjoint(with: catalog.showcase(of: event)))
    }

    /// Seven items leave four outside the showcase, so nothing is borrowed from it, and none of the
    /// seven has a big step goal, so the last of the four is the centrepiece.
    @Test
    func anEventWithFourPiecesBesidesItsShowcaseBorrowsNothing() throws {
        let bundled = catalog()
        let event = try #require(bundled.event(id: "halloween-2026"))
        let items = Array(bundled.items(earnedIn: event).prefix(7))
        let trimmed = UnlockCatalog(version: bundled.version, events: [event], items: items)

        let selection = try #require(SellGearSelection(catalog: trimmed, today: day(2_026, 10, 15)))
        #expect(selection.centerpiece.item.id == "ghost_sheet")
        #expect(selection.companions.map(\.item.id) == ["pumpkin_ghost", "pumpkin_heirloom", "candy_corn"])
    }

    /// An event of three has nothing to borrow beyond itself: it draws what it has.
    @Test
    func anEventSmallerThanFourDrawsEveryPieceItHas() throws {
        let bundled = catalog()
        let event = try #require(bundled.event(id: "halloween-2026"))
        let items = Array(bundled.items(earnedIn: event).prefix(3))
        let trimmed = UnlockCatalog(version: bundled.version, events: [event], items: items)

        let selection = try #require(SellGearSelection(catalog: trimmed, today: day(2_026, 10, 15)))
        #expect(Set(selection.pieces.map(\.item)) == Set(items))
    }

    @Test
    func withNoEventRunningTheLatestFinishedOneIsUsed() {
        let bundled = catalog()
        let twoEvents = UnlockCatalog(
            version: bundled.version,
            events: bundled.events.filter { ["halloween-2026", "thanksgiving-2026"].contains($0.id) },
            items: bundled.items
        )

        #expect(SellGearSelection.event(in: twoEvents, today: day(2_027, 3, 1))?.id == "thanksgiving-2026")
    }

    @Test
    func beforeAnyEventHasOpenedThereIsNoGear() {
        #expect(SellGearSelection.event(in: catalog(), today: day(2_026, 8, 1)) == nil)
        #expect(SellGearSelection(catalog: catalog(), today: day(2_026, 8, 1)) == nil)
    }

    @Test
    func anEmptyCatalogueShowsNoGearInsteadOfFailing() {
        #expect(SellGearSelection(catalog: .empty, today: .now) == nil)
    }

    // MARK: - Reduce Motion

    @Test
    func reduceMotionKeepsFadesAndDropsZoomBobAndTilt() {
        #expect(SellMotion.heroStartScale(reduceMotion: true) == 1)
        #expect(SellMotion.heroStartScale(reduceMotion: false) == 1.15)
        #expect(SellMotion.gearBobDistance(reduceMotion: true) == 0)
        #expect(SellMotion.gearBobDistance(reduceMotion: false) == 10)
        #expect(SellMotion.cardTilt(-1.5, reduceMotion: true) == 0)
        #expect(SellMotion.cardTilt(-1.5, reduceMotion: false) == -1.5)
    }

    // MARK: - Chips

    @Test
    func voiceOverHearsWrittenWordsNotCapitalizedDisplayText() throws {
        #expect(SellGhostLabelChip.Kind.pacer(stepsPerMinute: 80).accessibilityLabel == "Pacer, 80 steps per minute")
        #expect(SellGhostLabelChip.Kind.personalBest.accessibilityLabel == "Your best")
        #expect(SellRecordCard.examples[0].accessibilitySummary.hasPrefix("All-time best, Most Steps in 60 Min, "))
        #expect(SellRecordCard.examples[2].accessibilitySummary.hasPrefix("2nd all-time, Most Steps in 60 Min, "))

        let selection = try #require(SellGearSelection(catalog: catalog(), today: day(2_026, 10, 15)))
        #expect(selection.centerpiece.spokenRequirement == "25K steps")
        #expect(selection.centerpiece.requirement == "25K STEPS")
    }

    @Test
    func theGhostChipsCarryTheLabelsTheMountainDraws() {
        #expect(SellGhostLabelChip.Kind.pacer(stepsPerMinute: 80).label == "PACER · 80 SPM")
        #expect(SellGhostLabelChip.Kind.personalBest.label == "YOUR BEST")
    }
}
