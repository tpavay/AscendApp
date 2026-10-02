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

    /// October's ladder: the open, climbs up to twenty, every day of the month, and steps up to a
    /// hundred thousand - and something for every slot, not only carried.
    @Test
    func halloweenHasALongLadderAndOutfits() throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        let event = try #require(catalog.event(id: "halloween-2026"))
        let items = catalog.items(earnedIn: event)
        #expect(Set(items.map(\.shape.slot)) == Set(AthleteGear.Slot.allCases))
        let everyDay = try #require(items.first { $0.earn.metric == .days && $0.earn.threshold == event.dayCount() })
        #expect(everyDay.earn.threshold == event.dayCount())
        #expect(UnlockCopy.requirement(everyDay, in: event) == "EVERY DAY")
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

    /// A retired item stops being earned, but whoever already owns it keeps it in the Locker,
    /// ready to wear or take off; a climber who never earned it no longer sees it offered.
    @Test
    func aRetiredItemStaysInTheLockerOnlyForThoseWhoOwnIt() {
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: [
            Self.item(.pumpkinGhost, .climbs, 1),
            Self.item(.pumpkinGiant, .steps, 50_000, status: .retired),
            Self.item(.pumpkinMidnight, .steps, 25_000, status: .hidden)
        ])

        #expect(catalog.items(earnedIn: Self.halloween).map(\.shape) == [.pumpkinGhost], "nobody earns a retired item")
        #expect(catalog.lockerItems(of: Self.halloween, owned: []).map(\.shape) == [.pumpkinGhost])
        #expect(catalog.lockerItems(of: Self.halloween, owned: [.pumpkinGiant]).map(\.shape) == [.pumpkinGhost, .pumpkinGiant])
        #expect(catalog.lockerItems(of: Self.halloween, owned: [.pumpkinMidnight]).map(\.shape) == [.pumpkinGhost], "a hidden item is never offered")
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
        #expect(UnlockCopy.nextLines(progress) == ["3 more climbs to the Heirloom Pumpkin", "23,000 more steps to the Giant Pumpkin"])
    }

    /// Every day of October means thirty-one different days with a finished climb; two climbs on
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

    @Test
    func requirementsReadTheWayTheyAreEarned() {
        #expect(UnlockCopy.requirement(Self.ladder[0]) == "OPEN ASCEND")
        #expect(UnlockCopy.requirement(Self.ladder[1]) == "1 CLIMB")
        #expect(UnlockCopy.requirement(Self.ladder[2]) == "5 CLIMBS")
        #expect(UnlockCopy.requirement(Self.ladder[3]) == "25K STEPS")
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

    private func store(enabled: Bool = true) -> (UnlockStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "UnlockTests-\(UUID().uuidString)")!
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder)
        return (UnlockStore(repository: FixedCatalog(catalog: catalog), defaults: defaults, isFlagEnabled: { enabled }), defaults)
    }

    @Test
    func openingAscendInOctoberEarnsThePumpkinAndShowsTheIntroOnce() {
        let (store, _) = store()
        store.recordVisit(userId: "climber", now: Self.date(10, 5), calendar: Self.utc)
        #expect(store.earned == [.pumpkinClassic])

        let intro = store.pendingIntro(userId: "climber", now: Self.date(10, 5), calendar: Self.utc)
        #expect(intro?.id == "halloween-2026")
        store.markIntroSeen(try! #require(intro), userId: "climber")
        #expect(store.pendingIntro(userId: "climber", now: Self.date(10, 6), calendar: Self.utc) == nil)
    }

    @Test
    func openingAscendOutsideAnEventEarnsNothing() {
        let (store, _) = store()
        store.recordVisit(userId: "climber", now: Self.date(9, 30), calendar: Self.utc)
        #expect(store.earned.isEmpty)
        #expect(store.pendingIntro(userId: "climber", now: Self.date(9, 30), calendar: Self.utc) == nil)
    }

    /// The switch hides every surface: nothing is drawn, offered or earned on an open, and what
    /// was already earned is still there when it comes back.
    @Test
    func theKillSwitchHidesEverySurfaceAndKeepsWhatWasEarned() {
        let defaults = UserDefaults(suiteName: "UnlockTests-\(UUID().uuidString)")!
        let catalog = UnlockCatalog(version: 1, events: [Self.halloween], items: Self.ladder)
        let flag = Flag()
        let store = UnlockStore(repository: FixedCatalog(catalog: catalog), defaults: defaults, isFlagEnabled: { flag.enabled })
        store.recordVisit(userId: "climber", now: Self.date(10, 5), calendar: Self.utc)

        flag.enabled = false
        var look = AthleteLook.starting(for: .man)
        look.carry = .pumpkinClassic
        #expect(store.drawnGear(for: look).isEmpty)
        #expect(store.pendingIntro(userId: "climber", now: Self.date(10, 5), calendar: Self.utc) == nil)

        flag.enabled = true
        #expect(store.drawnGear(for: look) == [.pumpkinClassic])
        #expect(store.earned == [.pumpkinClassic])
    }

    /// Unlocks are remembered per account on the device, and signing out forgets them.
    @Test
    func unlocksAreTheAccountsAndSignOutForgetsThem() {
        let (store, defaults) = store()
        store.recordVisit(userId: "first", now: Self.date(10, 5), calendar: Self.utc)

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

    /// Climbs saved on October 1-3, before this build, credited on a first open on October 5:
    /// each climbing item is dated by the climb that crossed its threshold, the open-app item by
    /// the visit, and a date already remembered is never moved.
    @Test
    func anItemIsDatedByTheClimbThatEarnedItNotTheDayItWasNoticed() throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        (1...3).map { day in
            Workout(date: Self.date(10, day), duration: 1_200, steps: 10_000, floors: 500, source: .headphoneMotion)
        }.forEach(context.insert)
        try context.save()

        let (store, _) = store()
        store.recordVisit(userId: "climber", now: Self.date(10, 5), calendar: Self.utc)
        store.refresh(userId: "climber", modelContext: context, now: Self.date(10, 5), calendar: Self.utc)
        #expect(store.earned == [.pumpkinClassic, .pumpkinGhost, .pumpkinMidnight])
        #expect(store.earnedAt[.pumpkinClassic] == Self.date(10, 5), "the open-app item keeps the day of the visit")
        #expect(store.earnedAt[.pumpkinGhost] == Self.date(10, 1))
        #expect(store.earnedAt[.pumpkinMidnight] == Self.date(10, 3))

        context.insert(Workout(date: Self.date(10, 6), duration: 1_200, steps: 30_000, floors: 500, source: .headphoneMotion))
        try context.save()
        store.refresh(userId: "climber", modelContext: context, now: Self.date(10, 7), calendar: Self.utc)
        #expect(store.earnedAt[.pumpkinGiant] == Self.date(10, 6))
        #expect(store.earnedAt[.pumpkinGhost] == Self.date(10, 1), "a remembered date never moves")
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
