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
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let cards = SellRecordCard.examples

        #expect(cards.map(\.kicker) == ["ALL-TIME BEST", "ALL-TIME BEST", "2ND ALL-TIME", "2ND ALL-TIME"])
        #expect(cards.map(\.title) == [
            "Most Steps in 60 Min", "Fastest 3,000 Steps", "Most Steps in 60 Min", "Fastest 2,000 Steps"
        ])
        #expect(cards.map { $0.detail(calendar: calendar) } == [
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

    @Test
    func novemberIsTooSmallAnEventToShowGear() throws {
        let catalog = catalog()
        let event = try #require(SellGearSelection.event(in: catalog, today: day(2_026, 11, 4)))

        #expect(event.id == "thanksgiving-2026")
        #expect(catalog.items(earnedIn: event).count == 6)
        #expect(SellGearSelection(catalog: catalog, today: day(2_026, 11, 4)) == nil)
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

    /// Seven items is the smallest event with gear, and none of its seven has a big step goal, so
    /// the catalogue's last piece outside the showcase is the centrepiece.
    @Test
    func sevenLiveItemsIsTheSmallestEventThatShowsGear() throws {
        let bundled = catalog()
        let event = try #require(bundled.event(id: "halloween-2026"))
        let items = bundled.items(earnedIn: event)
        let trimmed = { (count: Int) in
            UnlockCatalog(version: bundled.version, events: [event], items: Array(items.prefix(count)))
        }

        #expect(SellGearSelection(catalog: trimmed(6), today: day(2_026, 10, 15)) == nil)

        let selection = try #require(SellGearSelection(catalog: trimmed(7), today: day(2_026, 10, 15)))
        #expect(selection.centerpiece.item.id == "ghost_sheet")
        #expect(selection.companions.map(\.item.id) == ["pumpkin_ghost", "pumpkin_heirloom", "candy_corn"])
    }

    @Test
    func withNoEventRunningTheLatestFinishedOneIsUsed() {
        #expect(SellGearSelection.event(in: catalog(), today: day(2_027, 3, 1))?.id == "thanksgiving-2026")
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
    func reduceMotionKeepsFadesAndDropsZoomBobTiltAndRise() {
        #expect(SellMotion.heroStartScale(reduceMotion: true) == 1)
        #expect(SellMotion.heroStartScale(reduceMotion: false) == 1.15)
        #expect(SellMotion.gearBobDistance(reduceMotion: true) == 0)
        #expect(SellMotion.gearBobDistance(reduceMotion: false) == 10)
        #expect(SellMotion.cardTilt(-1.5, reduceMotion: true) == 0)
        #expect(SellMotion.cardTilt(-1.5, reduceMotion: false) == -1.5)
        #expect(SellMotion.phoneRise(reduceMotion: true) == 0)
        #expect(SellMotion.phoneRise(reduceMotion: false) == 40)
    }

    // MARK: - Chips

    @Test
    func theGhostChipsCarryTheLabelsTheMountainDraws() {
        #expect(SellGhostLabelChip.Kind.pacer(stepsPerMinute: 80).label == "PACER · 80 SPM")
        #expect(SellGhostLabelChip.Kind.personalBest.label == "YOUR BEST")
    }
}
