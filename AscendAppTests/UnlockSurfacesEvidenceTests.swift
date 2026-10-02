import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence that the October unlock surfaces a climber meets read the way the catalogue says:
/// the first-open intro gives the Pumpkin for opening Ascend and lists what climbing earns, the
/// Locker shows a climb's earnings ready to wear and the rest locked with what earns them, a
/// retired item stays only with those who earned it before it retired, and a reopened climb's
/// summary reads as it did at the finish.
///
/// Both are the shipping views, fed the bundled catalogue. Photographs are written only when
/// `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct UnlockSurfacesEvidenceTests {
    private static let userId = "unlock-surfaces-evidence"

    @Test
    func theOctoberIntroGivesThePumpkinForOpeningAndListsWhatClimbingEarns() async throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        let event = try #require(catalog.events.first { $0.id == "halloween-2026" })
        let items = catalog.items(earnedIn: event)
        var carried: AthleteGear?

        let size = CGSize(width: 402, height: 2_000)
        try await RenderedScreen.host(
            UnlockEventIntroView(
                event: event,
                items: items,
                look: .starting(for: .man),
                earned: [.pumpkinClassic],
                onCarry: { carried = $0 },
                onClose: {}
            )
            .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("equip on your athlete") }
            #expect(copy.contains("october on ascend mountain"), "\(copy)")
            #expect(copy.contains("halloween is on"), "\(copy)")
            #expect(copy.contains("your pumpkin is in"), "\(copy)")
            #expect(copy.contains("opening ascend in october earned it"), "\(copy)")
            #expect(copy.contains("climb in october to earn more"), "\(copy)")
            for title in ["Ghost Pumpkin", "Witch Hat", "Giant Pumpkin", "Giant Jack-o'-Lantern", "Ember Trainers"] {
                #expect(copy.contains(title.lowercased()), "the ladder is missing \(title): \(copy)")
            }
            #expect(copy.contains("yours to keep"), "\(copy)")
            try screen.photograph(named: "unlock-october-intro")

            try activateAccessibilityElement(labelled: "EQUIP ON YOUR ATHLETE", in: screen.root)
            #expect(carried == .pumpkinClassic, "equipping from the intro carries the open-app Pumpkin")
        }
    }

    @Test
    func theLockerShowsWhatOneOctoberClimbEarned() async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        // Pinned inside the event window: dated `.now`, the climb would land in November from
        // 2026-11-01 and every October expectation below would fail.
        let octoberClimb = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
        context.insert(Workout(date: octoberClimb, duration: 1_500, steps: 12_000, floors: 600, source: .headphoneMotion))
        try context.save()

        UnlockStore.shared.clearAccountScopedState()
        defer { UnlockStore.shared.clearAccountScopedState() }
        let looks = AthleteLookStore(repository: NoSavedLook(), genderSource: { _ in .man }, defaults: UserDefaults(suiteName: "UnlockSurfaces-\(UUID().uuidString)")!)

        let size = CGSize(width: 402, height: 1_400)
        try await RenderedScreen.host(
            LockerView(userId: Self.userId, store: looks)
                .modelContainer(container)
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy(reading: 400) { $0.contains("ghost pumpkin") && $0.contains("earned") }
            #expect(copy.contains("wear what you earned"), "\(copy)")
            #expect(copy.contains("pumpkin earned") || copy.contains("pumpkin, earned"), "the open-app Pumpkin is earned by any October climb: \(copy)")
            #expect(copy.contains("ghost pumpkin"), "\(copy)")
            #expect(copy.contains("locked"), "items the climb has not reached stay locked: \(copy)")
            #expect(UnlockStore.shared.earned.isSuperset(of: [.pumpkinClassic, .pumpkinGhost, .chocolateBar]))
            #expect(!UnlockStore.shared.earned.contains(.pumpkinGiant), "12,000 steps is short of the Giant Pumpkin")
            // An earned card has no progress bar, a locked one does; a row still lines up.
            let titles = Set(AthleteGear.allCases.map(\.title))
            let cardFrames = try await screen.elements(reading: 400).compactMap { element -> (String, CGRect)? in
                guard let label = element.accessibilityLabel, titles.contains(label) else { return nil }
                return (label, element.accessibilityFrame)
            }
            let heights = cardFrames.map { $0.1.height.rounded() }
            #expect(cardFrames.count >= 4 && Set(heights).count == 1, "every Locker card is the same height, earned or locked: \(cardFrames.map { "\($0.0) \($0.1.integral)" })")
            try screen.photograph(named: "unlock-locker-carry-earned")
        }
    }

    /// The build reaches a climber mid-October, after three climbs saved on a build that had no
    /// unlocks at all, one of them a live climb stopped short. On the first open of the new build
    /// all three count: three climbs, 25,000 steps, three days. The intro says what they already
    /// earned rather than leaving it to be found, and the Locker has those items ready to wear.
    @Test
    func climbsSavedBeforeTheUpdateCountOnTheFirstOpen() async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let stoppedShort = Workout(date: try Self.october(1), duration: 900, steps: 4_000, floors: 200, source: .headphoneMotion)
        stoppedShort.sourceMetadata = #"{"stopReason":"user_stopped","climbTargetStepCount":12000,"targetStepCount":12000}"#
        for climb in [stoppedShort,
                      Workout(date: try Self.october(2), duration: 1_800, steps: 9_000, floors: 450, source: .headphoneMotion),
                      Workout(date: try Self.october(3), duration: 2_400, steps: 12_000, floors: 600, source: .headphoneMotion)] {
            context.insert(climb)
        }
        try context.save()

        // First launch of the new build: nothing remembered, the open recorded, the climbs counted.
        let unlocks = try Self.freshDevice(retiring: [])
        let firstOpen = try Self.october(5)
        unlocks.recordVisit(userId: Self.userId, now: firstOpen)
        let progress = try #require(unlocks.refresh(userId: Self.userId, modelContext: context, now: firstOpen).first)
        #expect(progress.climbs == 3)
        #expect(progress.steps == 25_000)
        #expect(progress.climbedDays.count == 3)
        let creditedByClimbing: Set<AthleteGear> = [.pumpkinGhost, .witchHat, .chocolateBar, .pumpkinMidnight]
        #expect(unlocks.earned == creditedByClimbing.union([.pumpkinClassic]), "\(unlocks.earned)")

        let event = try #require(unlocks.catalog.events.first { $0.id == "halloween-2026" })
        let introSize = CGSize(width: 402, height: 2_000)
        try await RenderedScreen.host(
            UnlockEventIntroView(event: event, items: unlocks.catalog.items(earnedIn: event), look: .starting(for: .man),
                                 earned: unlocks.earned, onCarry: { _ in }, onClose: {})
                .frame(width: introSize.width, height: introSize.height),
            size: introSize,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("already earned") }
            #expect(copy.contains("your october climbs already earned 4 more"), "the intro says what earlier climbs earned: \(copy)")
            try screen.photograph(named: "unlock-update-midmonth-intro")
        }

        let lockerSize = CGSize(width: 402, height: 1_900)
        try await RenderedScreen.host(
            LockerView(userId: Self.userId, store: Self.looks(wearing: nil), unlocks: unlocks)
                .modelContainer(container)
                .frame(width: lockerSize.width, height: lockerSize.height),
            size: lockerSize,
            settle: .turns(40)
        ) { screen in
            let cards = try await Self.cards(on: screen) { $0["Midnight Pumpkin"] != nil }
            // The Locker opens on carried items; the Witch Hat is on the head tab, and earned above.
            for item in creditedByClimbing where item.slot == .carry {
                #expect(cards[item.title] == "Earned", "\(item.title) is earned by the climbs from before the update: \(cards)")
            }
            #expect(cards["Heirloom Pumpkin"] == "Locked", "five climbs is still two away: \(cards)")
            try screen.photograph(named: "unlock-update-midmonth-locker")
        }
    }

    /// Climbs saved on October 1-3, before the climber had this build, are first counted on an
    /// open on October 5. The back of the Ghost Pumpkin's card dates it by the climb that crossed
    /// its threshold, October 1, not by the day this device first noticed it.
    @Test
    func aCardBackDatesTheItemByTheClimbThatEarnedIt() async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        for day in 1...3 {
            context.insert(Workout(date: try Self.october(day), duration: 1_200, steps: 10_000, floors: 500, source: .headphoneMotion))
        }
        try context.save()

        let unlocks = try Self.freshDevice(retiring: [])
        let firstOpen = try Self.october(5)
        unlocks.recordVisit(userId: Self.userId, now: firstOpen)
        unlocks.refresh(userId: Self.userId, modelContext: context, now: firstOpen)
        #expect(unlocks.earnedAt[.pumpkinGhost] == (try Self.october(1)))
        #expect(unlocks.earnedAt[.pumpkinMidnight] == (try Self.october(3)))
        #expect(unlocks.earnedAt[.pumpkinClassic] == firstOpen, "the open-app Pumpkin keeps the day of the visit")

        let size = CGSize(width: 402, height: 1_900)
        try await RenderedScreen.host(
            LockerView(userId: Self.userId, revealing: .pumpkinGhost, store: Self.looks(wearing: nil), unlocks: unlocks)
                .modelContainer(container)
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            _ = try await Self.cards(on: screen) { $0["Midnight Pumpkin"] != nil }
            let text = try await screen.recognizedText(scale: 2)
            #expect(text.contains("earned oct 1"), "the Ghost Pumpkin's back reads the day of the climb that earned it: \(text)")
            #expect(!text.contains("earned oct 5"), "no card reads the day the device first noticed it: \(text)")
            try screen.photograph(named: "unlock-card-back-dated-by-crossing-climb")
        }
    }

    /// The Locker stage with the athlete holding each carried pumpkin, for the hand that closes
    /// around it: the shoulder carry and the overhead giant.
    @Test(arguments: [AthleteGear.pumpkinClassic, .pumpkinGiantLantern])
    func theLockerStageShowsTheHandClosedAroundTheCarriedPumpkin(item: AthleteGear) async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let unlocks = try Self.freshDevice(retiring: [])
        let size = CGSize(width: 402, height: 900)
        try await RenderedScreen.host(
            LockerView(userId: Self.userId, store: Self.looks(wearing: item), unlocks: unlocks)
                .modelContainer(container)
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(80)
        ) { screen in
            let cards = try await Self.cards(on: screen) { $0[item.title] == "Wearing" }
            #expect(cards[item.title] == "Wearing", "\(cards)")
            try screen.photograph(named: "unlock-locker-stage-holding-\(item.rawValue)")
        }
    }

    /// The Giant Pumpkin retired on October 20: a climber who passes 50,000 steps only after
    /// that day is never offered it, and one who passed it before keeps it on a fresh phone,
    /// earned back from the climbs restored there.
    @Test(arguments: [false, true])
    func aRetiredItemIsKeptOnlyByThoseWhoEarnedItBeforeItRetired(earnedBeforeRetiring: Bool) async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let climbs: [(day: Int, steps: Int)] = earnedBeforeRetiring ? [(5, 30_000), (19, 25_000)] : [(5, 40_000), (25, 20_000)]
        for climb in climbs {
            context.insert(Workout(date: try Self.october(climb.day), duration: 3_600, steps: climb.steps, floors: 2_000, source: .headphoneMotion))
        }
        try context.save()

        let unlocks = try Self.freshDevice(retiring: [(.pumpkinGiant, UnlockEvent.Day(year: 2026, month: 10, day: 20))])
        let size = CGSize(width: 402, height: 1_900)
        try await RenderedScreen.host(
            LockerView(userId: Self.userId, store: Self.looks(wearing: nil), unlocks: unlocks)
                .modelContainer(container)
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let cards = try await Self.cards(on: screen)
            if earnedBeforeRetiring {
                #expect(cards["Giant Pumpkin"] == "Earned", "passed 50,000 steps on October 19, before it retired: \(cards)")
                #expect(unlocks.earned.contains(.pumpkinGiant))
            } else {
                #expect(cards["Giant Pumpkin"] == nil, "50,000 steps passed only on October 25, after it retired: \(cards)")
                #expect(!unlocks.earned.contains(.pumpkinGiant))
            }
            #expect(cards["Midnight Pumpkin"] == "Earned", "a live item is still earned as before: \(cards)")
            try screen.photograph(named: earnedBeforeRetiring ? "unlock-retired-kept-by-pre-retirement-earner" : "unlock-retired-not-earned-after-retirement")
        }
    }

    /// A retired item the climber is wearing stays in the Locker, offered to be taken off, even
    /// when nothing on this device remembers earning it.
    @Test
    func aWornRetiredItemStaysInTheLockerToBeTakenOff() async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        container.mainContext.insert(Workout(date: try Self.october(15), duration: 1_500, steps: 6_000, floors: 300, source: .headphoneMotion))
        try container.mainContext.save()

        let unlocks = try Self.freshDevice(retiring: [(.pumpkinGiantLantern, nil)])
        let size = CGSize(width: 402, height: 1_900)
        try await RenderedScreen.host(
            LockerView(userId: Self.userId, store: Self.looks(wearing: .pumpkinGiantLantern), unlocks: unlocks)
                .modelContainer(container)
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let title = AthleteGear.pumpkinGiantLantern.title
            let worn = try await Self.cards(on: screen) { $0[title] == "Wearing" }
            #expect(worn[title] == "Wearing", "the worn retired item is offered so it can come off: \(worn)")
            #expect(!unlocks.earned.contains(.pumpkinGiantLantern))
            try screen.photograph(named: "unlock-retired-worn-still-in-locker")
        }
    }

    /// Climb 1 of five, reopened after the fifth: its summary still credits it with the Ghost
    /// Pumpkin it earned, and none of what the later climbs earned. Climb 4 earned nothing and
    /// reads where the climber stood after it, four climbs in.
    @Test
    func aReopenedClimbsSummaryShowsWhatItEarnedAtTheTime() async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let context = container.mainContext
        let climbs = try (1...5).map { day in
            Workout(date: try Self.october(day), duration: 1_200, steps: 6_000, floors: 300, source: .headphoneMotion)
        }
        climbs.forEach(context.insert)
        try context.save()

        let unlocks = try Self.freshDevice(retiring: [])
        let size = CGSize(width: 402, height: 640)

        try await RenderedScreen.host(
            UnlockFinishCard(workout: climbs[0], unlocks: unlocks, userId: { Self.userId })
                .modelContainer(container)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(Color.black),
            size: size,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("halloween unlock") }
            #expect(copy.contains("halloween unlock"), "\(copy)")
            #expect(copy.contains("ghost pumpkin"), "\(copy)")
            for later in ["Heirloom", "Midnight", "Witch Hat", "Chocolate"] {
                #expect(!copy.contains(later.lowercased()), "climb 1 is not credited with \(later): \(copy)")
            }
            try screen.photograph(named: "unlock-reopened-first-climb-summary")
        }

        try await RenderedScreen.host(
            UnlockFinishCard(workout: climbs[3], unlocks: unlocks, userId: { Self.userId })
                .modelContainer(container)
                .padding(16)
                .frame(width: size.width, height: 200)
                .background(Color.black),
            size: CGSize(width: size.width, height: 200),
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("climbs") }
            #expect(copy.contains("4 climbs"), "climb 4 reads four climbs in, not today's five: \(copy)")
            #expect(copy.contains("24,000 steps"), "\(copy)")
            #expect(copy.contains("1 more climb to the heirloom pumpkin"), "\(copy)")
            try screen.photograph(named: "unlock-reopened-fourth-climb-summary")
        }
    }

    private static func october(_ day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
    }

    /// A store on a device that has remembered nothing, reading the bundled Halloween ladder with
    /// `retiring` items retired on the given day.
    private static func freshDevice(retiring: [(AthleteGear, UnlockEvent.Day?)]) throws -> UnlockStore {
        let bundled = HostedUnlockCatalogRepository.bundledCatalog()
        let halloween = try #require(bundled.events.first { $0.id == "halloween-2026" })
        let items = bundled.items.filter { $0.earn.event == halloween.id }.map { item in
            guard let retired = retiring.first(where: { $0.0 == item.shape }) else { return item }
            return UnlockItem(id: item.id, shape: item.shape, slot: item.slot, rarity: item.rarity, status: .retired, retiredOn: retired.1, earn: item.earn)
        }
        let catalog = UnlockCatalog(version: bundled.version, events: [halloween], items: items)
        return UnlockStore(repository: FixedCatalog(catalog: catalog), defaults: UserDefaults(suiteName: "UnlockSurfaces-\(UUID().uuidString)")!, isFlagEnabled: { true })
    }

    private static func looks(wearing item: AthleteGear?) -> AthleteLookStore {
        var look = AthleteLook.starting(for: .man)
        if let item { look.equip(item) }
        return AthleteLookStore(repository: SavedLook(look: item == nil ? nil : look), genderSource: { _ in .man }, defaults: UserDefaults(suiteName: "UnlockSurfaces-\(UUID().uuidString)")!)
    }

    /// Each Locker card on screen, by item title, with what it says about it: Earned, Wearing, or
    /// Locked and what earns it.
    private static func cards(on screen: HostedScreen, until isReady: @escaping ([String: String]) -> Bool = { _ in true }) async throws -> [String: String] {
        let titles = Set(AthleteGear.allCases.map(\.title))
        func read(_ elements: [NSObject]) -> [String: String] {
            Dictionary(elements.compactMap { element in
                guard let label = element.accessibilityLabel, titles.contains(label), let value = element.accessibilityValue else { return nil }
                return (label, value.hasPrefix("Locked") ? "Locked" : value)
            }, uniquingKeysWith: { first, _ in first })
        }
        let elements = try await screen.elements(reading: 400) { elements in
            let cards = read(elements)
            return cards["Pumpkin"] != nil && isReady(cards)
        }
        return read(elements)
    }

    private struct FixedCatalog: UnlockCatalogRepository {
        let catalog: UnlockCatalog
        func loadInitialCatalog() -> UnlockCatalog { catalog }
        func refreshCatalog() async throws -> UnlockCatalog { catalog }
    }

    private struct SavedLook: AthleteLookRepository {
        let look: AthleteLook?
        func fetchLook(userId: String) async throws -> AthleteLook? { look }
        func saveLook(_ look: AthleteLook, userId: String) async throws {}
    }

    private struct NoSavedLook: AthleteLookRepository {
        func fetchLook(userId: String) async throws -> AthleteLook? { nil }
        func saveLook(_ look: AthleteLook, userId: String) async throws {}
    }
}
