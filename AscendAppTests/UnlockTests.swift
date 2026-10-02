import Foundation
import SwiftData
import simd
import Testing
@testable import AscendApp

/// The unlock catalogue, the event ladder it describes, and how the climber's own climbs earn
/// from it.
@MainActor
struct UnlockTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private static func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private static let halloween = UnlockEvent(
        id: "halloween-2026", title: "Halloween", monthName: "October",
        startsOn: .init(year: 2026, month: 10, day: 1), endsBefore: .init(year: 2026, month: 11, day: 1)
    )

    private static func item(_ shape: AthleteGear, _ metric: UnlockItem.Earn.Metric, _ threshold: Int, status: UnlockItem.Status = .live) -> UnlockItem {
        UnlockItem(id: shape.rawValue, shape: shape, status: status, earn: .init(path: .event, event: "halloween-2026", metric: metric, threshold: threshold))
    }

    private static let ladder = [
        item(.pumpkinClassic, .visits, 1),
        item(.pumpkinGhost, .climbs, 1),
        item(.pumpkinHeirloom, .climbs, 5),
        item(.pumpkinMidnight, .steps, 25_000),
        item(.pumpkinGiant, .steps, 50_000)
    ]

    // MARK: - Catalogue

    /// The app bundles the same file Hosting serves, so a device that never reached the network
    /// runs the same events; one copy edited without the other would split the fleet.
    @Test
    func theBundledCatalogueIsTheHostedOne() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let hosted = try Data(contentsOf: repo.appending(path: "web/public/unlocks/catalog.json"))
        let bundled = try Data(contentsOf: repo.appending(path: "AscendApp/Features/Athlete/Resources/unlock-catalog.json"))
        #expect(hosted == bundled)
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        #expect(catalog == (try JSONDecoder().decode(UnlockCatalog.self, from: hosted)))
        #expect(!catalog.items.isEmpty, "the bundle carries the catalogue")
    }

    /// October and November each give one item for showing up and the rest for climbing, and
    /// every item the catalogue names is one this build draws.
    @Test
    func eachEventGivesOneItemForOpeningAndTheRestForClimbing() throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        #expect(catalog.events.map(\.id) == ["halloween-2026", "thanksgiving-2026"])
        for event in catalog.events {
            let items = catalog.items(earnedIn: event)
            #expect(items.filter { $0.earn.metric == .visits }.count == 1, "\(event.id) gives one item for opening Ascend")
        }
        #expect(Set(catalog.items.map(\.shape)) == Set(AthleteGear.allCases))
        #expect(Set(catalog.items.map(\.id)).count == catalog.items.count)
    }

    /// October's ladder: the open, climbs up to twenty, twenty days of the month, and steps up to a
    /// hundred thousand - and something for every slot, not only carried.
    @Test
    func halloweenHasALongLadderAndOutfits() throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        let event = try #require(catalog.event(id: "halloween-2026"))
        let items = catalog.items(earnedIn: event)
        #expect(Set(items.map(\.shape.slot)) == Set(AthleteGear.Slot.allCases))
        let pumpkinHead = try #require(items.first { $0.shape == .pumpkinHead })
        #expect(pumpkinHead.earn.metric == .days)
        #expect(pumpkinHead.earn.threshold == 20)
        #expect(UnlockCopy.threshold(pumpkinHead, in: event) == "20 days", "a bare count like every other tile")
        #expect(UnlockCopy.rule(pumpkinHead, in: event) == "20 days in October")
        #expect(items.map(\.earn.threshold).max() == 100_000)
    }

    /// A newer catalogue can name shapes, slots and ways of earning this build has never heard of;
    /// those items are skipped and the rest of the catalogue still loads.
    @Test
    func anItemThisBuildCannotDrawIsSkippedNotFatal() throws {
        let json = """
        {"version": 2, "events": [{"id": "e", "title": "E", "monthName": "December", "startsOn": "2026-12-01", "endsBefore": "2027-01-01"}],
         "items": [
          {"id": "a", "shape": "pumpkin_classic", "slot": "carry", "status": "live", "earn": {"path": "event", "event": "e", "metric": "climbs", "threshold": 1}},
          {"id": "b", "shape": "snowman", "slot": "carry", "status": "live", "earn": {"path": "event", "event": "e", "metric": "climbs", "threshold": 1}},
          {"id": "c", "shape": "pumpkin_ghost", "slot": "hat", "status": "live", "earn": {"path": "event", "event": "e", "metric": "climbs", "threshold": 1}},
          {"id": "d", "shape": "pumpkin_ghost", "slot": "carry", "status": "live", "earn": {"path": "streak", "event": "e", "metric": "weeks", "threshold": 4}},
          {"id": "e", "shape": "pumpkin_ghost", "slot": "carry", "status": "hidden", "earn": {"path": "event", "event": "e", "metric": "steps", "threshold": 0}},
          {"id": "f", "shape": "witch_hat", "slot": "carry", "status": "live", "earn": {"path": "event", "event": "e", "metric": "climbs", "threshold": 1}}
         ]}
        """
        let catalog = try JSONDecoder().decode(UnlockCatalog.self, from: Data(json.utf8))
        #expect(catalog.items.map(\.id) == ["a"])
    }

    /// Shipped dark: an item the file has not switched on is neither offered nor earnable.
    @Test
    func onlyLiveItemsAreOffered() {
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: [
            Self.item(.pumpkinGhost, .climbs, 1),
            Self.item(.pumpkinGiant, .steps, 50_000, status: .hidden)
        ])
        #expect(catalog.items(earnedIn: Self.halloween).map(\.shape) == [.pumpkinGhost])
    }

    /// A retired item stops being earned, but whoever already owns it keeps it in Your Athlete,
    /// ready to wear or take off; a climber who never earned it no longer sees it offered.
    @Test
    func aRetiredItemStaysInYourAthleteOnlyForThoseWhoOwnIt() {
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: [
            Self.item(.pumpkinGhost, .climbs, 1),
            Self.item(.pumpkinGiant, .steps, 50_000, status: .retired),
            Self.item(.pumpkinMidnight, .steps, 25_000, status: .hidden)
        ])

        #expect(catalog.items(earnedIn: Self.halloween).map(\.shape) == [.pumpkinGhost], "nobody earns a retired item")
        #expect(catalog.gearItems(of: Self.halloween, owned: []).map(\.shape) == [.pumpkinGhost])
        #expect(catalog.gearItems(of: Self.halloween, owned: [.pumpkinGiant]).map(\.shape) == [.pumpkinGhost, .pumpkinGiant])
        #expect(catalog.gearItems(of: Self.halloween, owned: [.pumpkinMidnight]).map(\.shape) == [.pumpkinGhost], "a hidden item is never offered")
    }

    private static let retiredGiant = UnlockCatalog(version: 1, events: [halloween], items: [
        item(.pumpkinGhost, .climbs, 1),
        UnlockItem(
            id: "pumpkin_giant", shape: .pumpkinGiant, status: .retired, retiredOn: .init(year: 2026, month: 10, day: 20),
            earn: .init(path: .event, event: "halloween-2026", metric: .steps, threshold: 50_000)
        )
    ])

    /// Steps climbed after the retirement day count toward nothing: crossing the threshold then
    /// does not earn the item.
    @Test
    func crossingTheThresholdAfterRetirementDoesNotEarnIt() {
        let climbs = [
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 5), steps: 40_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 20, 0), steps: 5_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 25), steps: 20_000)
        ]
        #expect(Self.retiredGiant.retiredItems(earnedIn: Self.halloween, by: climbs, calendar: Self.utc).isEmpty)
    }

    /// A climber who earned the item before it was retired earns it back on a new phone, from the
    /// climbs restored there.
    @Test
    func aPreRetirementEarnerKeepsItOnAFreshDevice() {
        let climbs = [
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 5), steps: 30_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 19, 23), steps: 25_000)
        ]
        #expect(Self.retiredGiant.retiredItems(earnedIn: Self.halloween, by: climbs, calendar: Self.utc) == [.pumpkinGiant])

        let undated = UnlockCatalog(version: 1, events: [Self.halloween], items: [Self.item(.pumpkinGiant, .steps, 50_000, status: .retired)])
        #expect(undated.retiredItems(earnedIn: Self.halloween, by: climbs, calendar: Self.utc).isEmpty, "with no date, only a remembered unlock keeps it")
    }

    /// The catalogue names the retirement day the same way it names an event's days.
    @Test
    func aRetirementDayIsReadFromTheCatalogue() throws {
        let json = """
        {"id": "g", "shape": "pumpkin_giant", "slot": "carry", "status": "retired", "retiredOn": "2026-10-20",
         "earn": {"path": "event", "event": "halloween-2026", "metric": "steps", "threshold": 50000}}
        """
        let item = try JSONDecoder().decode(UnlockItem.self, from: Data(json.utf8))
        #expect(item.retiredOn == UnlockEvent.Day(year: 2026, month: 10, day: 20))
    }

    /// The event runs on the climber's own calendar: the first second of October 1 to the last of
    /// October 31.
    @Test
    func anEventCoversItsDaysInTheClimbersCalendar() {
        let calendar = Self.utc
        #expect(Self.halloween.contains(Self.date(10, 1, 0), calendar: calendar))
        #expect(Self.halloween.contains(Self.date(10, 31, 23), calendar: calendar))
        #expect(!Self.halloween.contains(Self.date(9, 30, 23), calendar: calendar))
        #expect(!Self.halloween.contains(Self.date(11, 1, 0), calendar: calendar))
    }

    // MARK: - Ladder

    /// Every kind of climb Ascend saves counts - a Live Climb, a Just Climb, a routine, and a
    /// session recovered after the app was closed - because every in-app sensor flow saves its
    /// climb the same way. Rows from before manual logging and Apple Health import were removed
    /// are not climbs Ascend recorded, and never count.
    @Test
    func everyKindOfSavedClimbCounts() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let kinds = [
            #"{"trackingMode":"live_climb","stopReason":"target_reached"}"#,
            #"{"trackingMode":"just_climb","stopReason":"user_stopped"}"#,
            #"{"trackingMode":"routine","stopReason":"skipped"}"#,
            #"{"trackingMode":"live_climb","stopReason":"interrupted"}"#
        ]
        let saved = kinds.enumerated().map { index, metadata in
            let climb = Workout(date: Self.date(10, index + 1), duration: 900, steps: 2_000, floors: 100, source: .headphoneMotion)
            climb.sourceMetadata = metadata
            return climb
        }
        saved.forEach(context.insert)
        context.insert(Workout(date: Self.date(10, 6), duration: 900, steps: 2_000, floors: 100, source: .manual))
        context.insert(Workout(date: Self.date(10, 7), duration: 900, steps: 2_000, floors: 100, source: .appleHealth))
        try context.save()

        let climbs = try UnlockClimbQuery.climbs(in: Self.halloween, calendar: Self.utc, modelContext: context)
        #expect(Set(climbs.map(\.id)) == Set(saved.map(\.id)))
    }

    /// Any climb saved with progress counts, whether it reached the top or not: a live climb
    /// stopped short at 4,000 of the climb's 12,000 steps and saved advances the climbs, steps and
    /// days ladders exactly as a finished one would. A climb with no steps is not progress.
    @Test
    func everyClimbSavedWithProgressCountsFinishedOrNot() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let stoppedShort = Workout(date: Self.date(10, 6), duration: 900, steps: 4_000, floors: 200, source: .headphoneMotion)
        stoppedShort.sourceMetadata = #"{"stopReason":"user_stopped","climbTargetStepCount":12000,"targetStepCount":12000}"#
        let finished = Workout(date: Self.date(10, 8), duration: 2_400, steps: 12_000, floors: 600, source: .headphoneMotion)
        let noProgress = Workout(date: Self.date(10, 10), duration: 30, steps: 0, floors: 0, source: .headphoneMotion)
        [stoppedShort, finished, noProgress].forEach(context.insert)
        try context.save()

        let climbs = try UnlockClimbQuery.climbs(in: Self.halloween, calendar: Self.utc, modelContext: context)
        #expect(Set(climbs.map(\.id)) == [stoppedShort.id, finished.id], "the stopped climb counts and the empty one does not")

        let ladder = [
            Self.item(.pumpkinGhost, .climbs, 2),
            Self.item(.pumpkinMidnight, .steps, 16_000),
            Self.item(.witchHat, .days, 2)
        ]
        let progress = UnlockEventProgress(event: Self.halloween, items: ladder, climbs: climbs, visited: false, calendar: Self.utc)
        #expect(progress.climbs == 2)
        #expect(progress.steps == 16_000)
        #expect(progress.earned == [.pumpkinGhost, .pumpkinMidnight, .witchHat], "the stopped climb's steps and day count toward the ladder")

        let alone = try UnlockClimbQuery.climbs(in: Self.halloween, calendar: Self.utc, modelContext: context).filter { $0.id == stoppedShort.id }
        #expect(UnlockEventProgress(event: Self.halloween, items: [Self.item(.pumpkinGhost, .climbs, 1)], climbs: alone, visited: false, calendar: Self.utc).earned == [.pumpkinGhost],
                "one stopped-short climb on its own is a climb")
    }

    @Test
    func climbsAndStepsInsideTheEventEarnTheirRungs() {
        let climbs = [
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(9, 30), steps: 90_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 2), steps: 3_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 9), steps: 24_000)
        ]
        let progress = UnlockEventProgress(event: Self.halloween, items: Self.ladder, climbs: climbs, visited: false, calendar: Self.utc)

        #expect(progress.climbs == 2, "September's climb is not October's")
        #expect(progress.steps == 27_000)
        #expect(progress.earned == [.pumpkinClassic, .pumpkinGhost, .pumpkinMidnight], "a climb in October is also a visit")
        #expect(progress.nextItems.map(\.item.shape) == [.pumpkinHeirloom, .pumpkinGiant])
        #expect(progress.nextItems.map(\.remaining) == [3, 23_000])
        #expect(UnlockCopy.nextLines(progress) == ["3 more climbs to the Heirloom Pumpkin", "23,000 more steps to The Giant"])
    }

    /// Every day of October means thirty-one different days with a saved climb; two climbs on
    /// one day count once.
    @Test
    func daysCountDifferentDaysNotClimbs() {
        let everyDay = Self.item(.pumpkinHead, .days, 3)
        let climbs = [Self.date(10, 1, 8), Self.date(10, 1, 20), Self.date(10, 2), Self.date(10, 4)].map {
            UnlockEventProgress.Climb(id: UUID(), date: $0, steps: 3_000)
        }
        let progress = UnlockEventProgress(event: Self.halloween, items: [everyDay], climbs: climbs, visited: false, calendar: Self.utc)
        #expect(progress.days == 3)
        #expect(progress.earned == [.pumpkinHead])
        let short = UnlockEventProgress(event: Self.halloween, items: [everyDay], climbs: Array(climbs.prefix(3)), visited: false, calendar: Self.utc)
        #expect(UnlockCopy.nextLines(short) == ["1 more day climbing to the Pumpkin Head"])
    }

    @Test
    func openingTheAppAloneEarnsOnlyTheVisitItem() {
        let progress = UnlockEventProgress(event: Self.halloween, items: Self.ladder, climbs: [], visited: true, calendar: Self.utc)
        #expect(progress.earned == [.pumpkinClassic])
    }

    @Test
    func theClimbThatCrossesARungIsTheOneThatEarnedIt() {
        let first = UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 2), steps: 12_000)
        let second = UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 3), steps: 14_000)
        let before = UnlockEventProgress(event: Self.halloween, items: Self.ladder, climbs: [first], visited: true, calendar: Self.utc)
        let after = UnlockEventProgress(event: Self.halloween, items: Self.ladder, climbs: [first, second], visited: true, calendar: Self.utc)
        #expect(after.newlyEarned(since: before) == [.pumpkinMidnight])
        #expect(after.newlyEarned(since: after).isEmpty)
    }

    /// Thresholds read as bare counts, and the item's own rule names the month.
    @Test
    func thresholdsReadAsBareCounts() {
        #expect(Self.ladder.map { UnlockCopy.threshold($0, in: Self.halloween) } == ["Open Ascend", "1 climb", "5 climbs", "25K steps", "50K steps"])
        #expect(UnlockCopy.rule(Self.ladder[2], in: Self.halloween) == "5 climbs in October")
        #expect(UnlockCopy.rule(Self.ladder[0], in: Self.halloween) == "Open Ascend in October")
        let halloweenNight = Self.item(.emberTrainers, .onDay, 31)
        #expect(UnlockCopy.rule(halloweenNight, in: Self.halloween) == "Climb on October 31")
        #expect(UnlockCopy.slotLine(.pumpkinClassic) == "CARRIED ON YOUR SHOULDER")
        #expect(UnlockCopy.slotLine(.pumpkinGiant) == "HELD OVER YOUR HEAD")
        #expect(UnlockCopy.slotLine(.witchHat) == "WORN ON YOUR HEAD")
        #expect(UnlockCopy.slotLine(.ghostSheet) == "WORN AS YOUR KIT")
        #expect(UnlockCopy.slotLine(.glowTrainers) == "ON YOUR FEET")
        #expect(UnlockCopy.earnedLine(earned: 4, of: 15) == "4 of 15 earned. Climb for the rest.")
        #expect(UnlockCopy.earnedLine(earned: 15, of: 15) == "All 15 earned.")
        #expect(UnlockCopy.daysLeft(29) == "29 DAYS LEFT")
        #expect(UnlockCopy.daysLeft(1) == "LAST DAY")
    }

    /// The October page's ladders: every item on exactly one - showing up and climbs, steps,
    /// days - in the order they are earned, each earned, next, or locked.
    @Test
    func everyItemSitsOnOneLadderInTheOrderItIsEarned() throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        let event = try #require(catalog.event(id: "halloween-2026"))
        let items = catalog.items(earnedIn: event)
        let climbs = [
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 1), steps: 4_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 2), steps: 9_000),
            UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 3), steps: 12_000)
        ]
        let progress = UnlockEventProgress(event: event, items: items, climbs: climbs, visited: false, calendar: Self.utc)
        let ladders = UnlockLadder.ladders(for: progress)
        #expect(ladders.map(\.kind) == [.climbs, .steps, .days])
        #expect(ladders.flatMap(\.items).count == items.count, "every item is on one ladder")
        let climbsLadder = ladders[0], stepsLadder = ladders[1], daysLadder = ladders[2]
        #expect(climbsLadder.items.map(\.shape) == [.pumpkinClassic, .pumpkinGhost, .witchHat, .pumpkinHeirloom, .pumpkinLantern, .candyCorn, .ghostSheet])
        #expect(stepsLadder.items.map(\.shape) == [.chocolateBar, .pumpkinMidnight, .pumpkinGiant, .glowTrainers, .pumpkinGiantLantern])
        #expect(daysLadder.items.map(\.shape) == [.witchingShorts, .pumpkinHead, .emberTrainers])
        #expect((climbsLadder.count, stepsLadder.count, daysLadder.count) == (3, 25_000, 3))
        #expect(climbsLadder.state(of: climbsLadder.items[2]) == .earned)
        #expect(climbsLadder.state(of: climbsLadder.items[3]) == .next, "the Heirloom Pumpkin is next")
        #expect(climbsLadder.state(of: climbsLadder.items[4]) == .locked)
        #expect(stepsLadder.state(of: stepsLadder.items[2]) == .next, "The Giant is next")
        #expect(abs(stepsLadder.fraction - 0.25) < 1e-9, "the bar measures the way to the ladder's last rung")
        #expect(daysLadder.goal == 20)

        let short = try #require(UnlockItemProgress(item: climbsLadder.items[3], progress: progress))
        #expect((short.have, short.need, short.remaining, short.unit) == (3, 5, 2, "climbs"))
        #expect(UnlockItemProgress(item: daysLadder.items[2], progress: progress) == nil, "a named day is not counted toward")
    }

    @Test
    func daysLeftCountsTodayAndStopsAtTheEnd() {
        #expect(Self.halloween.daysLeft(now: Self.date(10, 2), calendar: Self.utc) == 30)
        #expect(Self.halloween.daysLeft(now: Self.date(10, 31, 23), calendar: Self.utc) == 1)
        #expect(Self.halloween.daysLeft(now: Self.date(11, 2), calendar: Self.utc) == 0)
    }

    // MARK: - Store

    @MainActor
    private final class Flag {
        var enabled = true
    }

    private struct FixedCatalog: UnlockCatalogRepository {
        let catalog: UnlockCatalog
        func loadInitialCatalog() -> UnlockCatalog { catalog }
        func refreshCatalog() async throws -> UnlockCatalog { catalog }
    }

    /// The day the store believes it is, moved by a test.
    @MainActor
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private func store(enabled: Bool = true, clock: Clock = Clock(UnlockTests.date(10, 5))) -> (UnlockStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "UnlockTests-\(UUID().uuidString)")!
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder)
        return (UnlockStore(repository: FixedCatalog(catalog: catalog), defaults: defaults, isFlagEnabled: { enabled }, now: { clock.date }), defaults)
    }

    @Test
    func openingAscendInOctoberEarnsThePumpkinAndShowsTheIntroOnce() {
        let clock = Clock(Self.date(10, 5))
        let (store, _) = store(clock: clock)
        store.recordVisit(userId: "climber", calendar: Self.utc)
        #expect(store.earned == [.pumpkinClassic])

        let intro = store.pendingIntro(userId: "climber", calendar: Self.utc)
        #expect(intro?.id == "halloween-2026")
        store.markIntroSeen(try! #require(intro), userId: "climber")
        clock.date = Self.date(10, 6)
        #expect(store.pendingIntro(userId: "climber", calendar: Self.utc) == nil)
    }

    @Test
    func openingAscendOutsideAnEventEarnsNothing() {
        let (store, _) = store(clock: Clock(Self.date(9, 30)))
        store.recordVisit(userId: "climber", calendar: Self.utc)
        #expect(store.earned.isEmpty)
        #expect(store.pendingIntro(userId: "climber", calendar: Self.utc) == nil)
    }

    /// The switch hides every surface: nothing is drawn, offered or earned on an open, and what
    /// was already earned is still there when it comes back.
    @Test
    func theKillSwitchHidesEverySurfaceAndKeepsWhatWasEarned() {
        let defaults = UserDefaults(suiteName: "UnlockTests-\(UUID().uuidString)")!
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder)
        let flag = Flag()
        let store = UnlockStore(repository: FixedCatalog(catalog: catalog), defaults: defaults, isFlagEnabled: { flag.enabled }, now: { Self.date(10, 5) })
        store.recordVisit(userId: "climber", calendar: Self.utc)

        flag.enabled = false
        var look = AthleteLook.starting(for: .man)
        look.carry = .pumpkinClassic
        #expect(store.drawnGear(for: look).isEmpty)
        #expect(store.pendingIntro(userId: "climber", calendar: Self.utc) == nil)

        flag.enabled = true
        #expect(store.drawnGear(for: look) == [.pumpkinClassic])
        #expect(store.earned == [.pumpkinClassic])
    }

    /// Unlocks are remembered per account on the device, and signing out forgets them.
    @Test
    func unlocksAreTheAccountsAndSignOutForgetsThem() {
        let (store, defaults) = store()
        store.recordVisit(userId: "first", calendar: Self.utc)

        let reopened = UnlockStore(
            repository: FixedCatalog(catalog: UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder)),
            defaults: defaults,
            isFlagEnabled: { true }
        )
        reopened.load(userId: "first")
        #expect(reopened.earned == [.pumpkinClassic], "an unlock outlives a relaunch")
        reopened.load(userId: "second")
        #expect(reopened.earned.isEmpty, "another account never sees the first one's")

        store.clearAccountScopedState()
        #expect(defaults.data(forKey: UnlockStore.earnedKey) == nil)
        #expect(store.earned.isEmpty)
    }

    /// An earned item reads NEW until the climber looks at it, across a relaunch; signing out
    /// forgets it with everything else.
    @Test
    func anEarnedItemIsNewUntilLookedAt() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        context.insert(Workout(date: Self.date(10, 1), duration: 1_200, steps: 10_000, floors: 500, source: .headphoneMotion))
        try context.save()

        let (store, defaults) = store()
        store.recordVisit(userId: "climber", calendar: Self.utc)
        store.refresh(userId: "climber", modelContext: context, calendar: Self.utc)
        #expect(store.newItems(wearing: []) == [.pumpkinClassic, .pumpkinGhost])
        store.markSeen([.pumpkinGhost, .pumpkinGiant], userId: "climber")
        #expect(store.newItems(wearing: []) == [.pumpkinClassic], "only earned items are marked; an unearned one stays unseen")

        let reopened = UnlockStore(repository: FixedCatalog(catalog: UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder)), defaults: defaults, isFlagEnabled: { true })
        reopened.load(userId: "climber")
        #expect(reopened.newItems(wearing: []) == [.pumpkinClassic], "what was looked at stays looked at after a relaunch")

        store.clearAccountScopedState()
        #expect(store.newItems(wearing: []).isEmpty)
    }

    /// The Profile pill counts only what Your Athlete can show as NEW: an item the athlete is
    /// wearing reads ON there, so it never counts, and an item the catalogue later hides is not
    /// drawn there, so it never counts either.
    @Test
    func theNewCountMatchesWhatYourAthleteShowsAsNew() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        context.insert(Workout(date: Self.date(10, 1), duration: 1_200, steps: 30_000, floors: 500, source: .headphoneMotion))
        try context.save()

        let (store, defaults) = store()
        store.refresh(userId: "climber", modelContext: context, calendar: Self.utc)
        #expect(store.newItems(wearing: []) == [.pumpkinClassic, .pumpkinGhost, .pumpkinMidnight])
        #expect(store.newItems(wearing: [.pumpkinGhost]) == [.pumpkinClassic, .pumpkinMidnight], "an item on the athlete is never new")

        let hiding = UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder.map { item in
            item.shape == .pumpkinMidnight ? Self.item(.pumpkinMidnight, .steps, 25_000, status: .hidden) : item
        })
        let later = UnlockStore(repository: FixedCatalog(catalog: hiding), defaults: defaults, isFlagEnabled: { true })
        later.load(userId: "climber")
        #expect(later.earned.contains(.pumpkinMidnight))
        #expect(later.newItems(wearing: []) == [.pumpkinClassic, .pumpkinGhost], "an item Your Athlete does not draw is never counted")
    }

    /// The finish screen's outcome counts the store's own climbs inside the event, and only the
    /// climb that crossed a rung is credited with it.
    @Test
    func aFinishedClimbReportsWhatItEarned() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let earlier = Workout(date: Self.date(10, 3), duration: 1_200, steps: 3_000, floors: 150, source: .headphoneMotion)
        let imported = Workout(date: Self.date(10, 3), duration: 1_200, steps: 60_000, floors: 150, source: .appleHealth)
        let finished = Workout(date: Self.date(10, 4), duration: 1_200, steps: 3_200, floors: 150, source: .headphoneMotion)
        [earlier, imported, finished].forEach(context.insert)
        try context.save()

        let (store, _) = store()
        let outcome = try #require(store.outcome(of: finished, userId: "climber", modelContext: context, calendar: Self.utc))
        #expect(outcome.progress.climbs == 2, "only climbs Ascend recorded count")
        #expect(outcome.progress.steps == 6_200)
        #expect(outcome.newlyEarned.isEmpty, "the first climb already earned the visit and the 1-climb rungs")
        #expect(store.earned == [.pumpkinClassic, .pumpkinGhost])

        let september = Workout(date: Self.date(9, 20), duration: 1_200, steps: 3_000, floors: 150, source: .headphoneMotion)
        context.insert(september)
        #expect(store.outcome(of: september, userId: "climber", modelContext: context, calendar: Self.utc) == nil)
    }

    /// A summary reopened after later climbs reads as it did at the finish: it counts only the
    /// climbs up to it, and is credited only with what it earned itself.
    @Test
    func aReopenedClimbReadsAsItDidAtTheFinish() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let climbs = (1...5).map { day in
            Workout(date: Self.date(10, day), duration: 1_200, steps: 6_000, floors: 150, source: .headphoneMotion)
        }
        climbs.forEach(context.insert)
        try context.save()

        let (store, _) = store()
        let first = try #require(store.outcome(of: climbs[0], userId: "climber", modelContext: context, calendar: Self.utc))
        #expect(first.progress.climbs == 1)
        #expect(first.progress.steps == 6_000)
        #expect(first.newlyEarned == [.pumpkinClassic, .pumpkinGhost])

        let fifth = try #require(store.outcome(of: climbs[4], userId: "climber", modelContext: context, calendar: Self.utc))
        #expect(fifth.progress.climbs == 5)
        #expect(fifth.newlyEarned == [.pumpkinHeirloom, .pumpkinMidnight])
    }

    // MARK: - Drawing

    /// Every item is a few thousand triangles at most, shared by everyone who carries it, so a
    /// pack of carriers costs less than one more athlete.
    @Test(arguments: AthleteGear.allCases.filter(\.isWornShape))
    func everyItemIsCheapAndRestsOnItsSeat(gear: AthleteGear) {
        let model = MountainGearModel.model(for: gear)
        #expect(model.triangleCount > 0)
        #expect(model.triangleCount < 6_000)
        let lowest = model.parts.flatMap(\.geometry.positions).map(\.y).min() ?? 0
        if gear.slot == .carry {
            #expect(lowest > -0.06, "a carried item rests on its seat rather than hanging through it")
        }
        for part in model.parts {
            #expect(part.geometry.normals.count == part.geometry.positions.count)
            #expect(part.geometry.uvs.count == part.geometry.positions.count)
            #expect(part.geometry.indices.allSatisfy { Int($0) < part.geometry.positions.count })
        }
    }

    @Test
    func onlyTheCarvedPumpkinsGlow() {
        let glowing = AthleteGear.allCases.filter { MountainGearModel.model(for: $0).glow != nil }
        #expect(glowing == [.pumpkinGhost, .pumpkinLantern, .pumpkinMidnight, .pumpkinGiantLantern, .pumpkinHead])
        #expect(MountainGearModel.PumpkinSkin.midnight.glow == MountainColor(hex: "#86D30A"), "the midnight pumpkin glows Ascend lime")
    }

    /// The lathe's triangles face outward, so the renderer's back-face culling keeps the skin.
    @Test
    func aLatheFacesOutward() {
        let ball = MountainGearGeometry.sphere(radius: 1, segments: 12)
        for start in stride(from: 0, to: ball.indices.count, by: 3) {
            let a = ball.positions[Int(ball.indices[start])]
            let b = ball.positions[Int(ball.indices[start + 1])]
            let c = ball.positions[Int(ball.indices[start + 2])]
            let normal = simd_cross(b - a, c - a)
            guard simd_length(normal) > 1e-6 else { continue }
            #expect(simd_dot(normal, (a + b + c) / 3) > 0)
        }
    }

    /// Kit is the athlete's own body redrawn in a colour that glows, never a shape of its own.
    @Test
    func kitIsDrawnOnTheBody() {
        let kit = AthleteGear.allCases.filter { !$0.isWornShape }
        #expect(Set(kit.map(\.slot)) == [.shorts, .trainers])
        #expect(kit.allSatisfy { MountainGearModel.model(for: $0).parts.isEmpty })
        #expect(kit.allSatisfy { MountainKitColor.glow($0) > 0 })
        var look = AthleteLook.starting(for: .man)
        look.equip(.witchingShorts)
        look.equip(.emberTrainers)
        #expect(MountainKitColor.item(forSlot: "bottom", look: look) == .witchingShorts)
        #expect(MountainKitColor.item(forSlot: "shoe", look: look) == .emberTrainers)
        #expect(MountainKitColor.item(forSlot: "top", look: look) == nil)
    }

    /// Climbing on one named day earns its item: Halloween is the 31st of October.
    @Test
    func aClimbOnHalloweenEarnsItsItem() {
        let halloweenNight = Self.item(.emberTrainers, .onDay, 31)
        let on31st = UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 31, 21), steps: 2_000)
        let on30th = UnlockEventProgress.Climb(id: UUID(), date: Self.date(10, 30, 21), steps: 2_000)
        #expect(UnlockEventProgress(event: Self.halloween, items: [halloweenNight], climbs: [on30th], visited: true, calendar: Self.utc).earned.isEmpty)
        #expect(UnlockEventProgress(event: Self.halloween, items: [halloweenNight], climbs: [on30th, on31st], visited: true, calendar: Self.utc).earned == [.emberTrainers])
    }

    /// Only the giants go overhead and the chocolate bar, cornucopia and pie are carried like a tray; everything else rides the
    /// shoulder, where the race camera behind the climber can see it.
    @Test
    func onlyTheGiantsArePressedOverhead() {
        #expect(AthleteGear.allCases.filter { $0.slot == .carry && $0.carry == .overhead } == [.pumpkinGiant, .pumpkinGiantLantern, .turkeyGiant])
        #expect(AthleteGear.allCases.filter { $0.slot == .carry && $0.carry == .tray } == [.chocolateBar, .cornucopia, .pumpkinPie])
    }

    /// The hands reach the item where the item sits: the shoulder hand cups it from outside, the
    /// palm on its flank and the fingers reaching up over its crown, and both hands take a giant's
    /// sides.
    @Test
    func theHandsHoldTheItemWhereItSits() throws {
        let shoulder = MountainCarryHold(carry: .shoulder, height: 0.2, halfWidth: 0.14)
        let turn = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        let seat = shoulder.seat(chest: SIMD3(0, 1.3, 0), chestTurn: turn, rightShoulder: SIMD3(-0.17, 1.45, 0))
        #expect(seat.y > 1.45, "it sits on top of the shoulder")
        let rightHand = try #require(shoulder.wrist(side: 1, seat: seat, chestTurn: turn))
        #expect(rightHand.x < seat.x - shoulder.body.halfWidth, "the palm is on the outside of the item")
        #expect((seat.y...seat.y + shoulder.body.top).contains(rightHand.y), "level with its body")
        let fingers = try #require(shoulder.fingers(side: 1, seat: seat, chestTurn: turn))
        #expect(fingers.y > seat.y + shoulder.body.top, "the fingers reach up over the crown")
        #expect(shoulder.wrist(side: 0, seat: seat, chestTurn: turn) == nil, "the other arm keeps swinging")

        let giant = MountainCarryHold(carry: .overhead, height: 0.45, halfWidth: 0.34)
        let overhead = giant.seat(chest: SIMD3(0, 1.3, 0), chestTurn: turn, rightShoulder: SIMD3(-0.17, 1.45, 0))
        let left = try #require(giant.wrist(side: 0, seat: overhead, chestTurn: turn))
        let right = try #require(giant.wrist(side: 1, seat: overhead, chestTurn: turn))
        #expect(left.x > 0.25 && right.x < -0.25, "a hand on each side")
        #expect(abs(left.y - right.y) < 1e-9)
    }
}

/// October's haunted stretch: the world it dresses, and only the steps it names.
struct MountainHauntedStretchTests {
    @Test
    func theStretchIsNightOverItsStepsAndTheMountainAsBeforeEitherSide() throws {
        let world = try MountainWorld.bundled()
        let dressed = MountainHauntedStretch.dress(world, from: 1_000, length: 5_000)
        #expect(dressed.haunted == 1_000..<6_000)
        for steps in [1_000.0, 3_500, 5_999] {
            #expect(dressed.regions.region(atSteps: steps).environment.sky == MountainHauntedStretch.sky)
            #expect(dressed.regions.region(atSteps: steps).environment.terrain == world.regions.region(atSteps: steps).environment.terrain,
                    "the slopes keep their shape; only the light and colour change")
        }
        for steps in [999.0, 6_000, 40_000] {
            #expect(dressed.regions.region(atSteps: steps).environment == world.regions.region(atSteps: steps).environment)
        }
    }

    @Test
    func lanternsLineOnlyTheStretch() throws {
        let dressed = MountainHauntedStretch.dress(try MountainWorld.bundled(), from: 0, length: 5_000)
        let inside = dressed.markers(near: 2_000).filter { $0.design == MountainHauntedStretch.lanternDesign }
        #expect(!inside.isEmpty)
        #expect(inside.allSatisfy { $0.step % MountainHauntedStretch.lanternEvery == 0 })
        #expect(!inside.contains { $0.step % 100 == 0 }, "the step posts and gates keep their own places")
        #expect(dressed.markers(near: 8_000).filter { $0.design == MountainHauntedStretch.lanternDesign }.isEmpty)
    }

    /// Halloween dresses the mountain; Thanksgiving does not.
    @Test
    func onlyHalloweenDressesTheMountain() throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        #expect(catalog.event(id: "halloween-2026")?.theme == UnlockEvent.Theme(style: .haunted, steps: 5_000))
        #expect(catalog.event(id: "thanksgiving-2026")?.theme == nil)
    }
}
