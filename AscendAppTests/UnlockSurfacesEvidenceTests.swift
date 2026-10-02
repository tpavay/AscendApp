import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence that the October surfaces a climber meets read the way the catalogue and their own
/// climbs say: the Home card, the October page and its ladders of the items themselves, an item
/// on the whole athlete with EQUIP, the gear inside Your Athlete with try-on, the NEW pill on
/// Profile, the first-open intro, retired items, and a reopened climb's summary.
///
/// Every view is the shipping one, fed the bundled catalogue. Photographs are written only when
/// `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct UnlockSurfacesEvidenceTests {
    private static let userId = "unlock-surfaces-evidence"

    /// Three climbs in the first days of October, one a live climb stopped short: 3 climbs,
    /// 25,000 steps, 3 days. That earns the Ghost Pumpkin, Witch Hat, Chocolate Bar and Midnight
    /// Pumpkin, with the Heirloom Pumpkin, The Giant and Witching Hour Shorts next.
    private static func threeEarlyOctoberClimbs() throws -> ModelContainer {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let stoppedShort = Workout(date: try october(1), duration: 900, steps: 4_000, floors: 200, source: .headphoneMotion)
        stoppedShort.sourceMetadata = #"{"stopReason":"user_stopped","climbTargetStepCount":12000,"targetStepCount":12000}"#
        for climb in [stoppedShort,
                      Workout(date: try october(2), duration: 1_800, steps: 9_000, floors: 450, source: .headphoneMotion),
                      Workout(date: try october(3), duration: 2_400, steps: 12_000, floors: 600, source: .headphoneMotion)] {
            container.mainContext.insert(climb)
        }
        try container.mainContext.save()
        return container
    }

    // MARK: - Home

    @Test
    func theHomeCardSaysHalloweenIsOnAndHowMuchIsEarned() async throws {
        let catalog = HostedUnlockCatalogRepository.bundledCatalog()
        let event = try #require(catalog.event(id: "halloween-2026"))
        var opened = false
        let size = CGSize(width: 402, height: 200)
        try await RenderedScreen.host(
            HomeEventCard(event: event, showcase: catalog.showcase(of: event), earned: 4, total: catalog.items(earnedIn: event).count, daysLeft: 29) {
                opened = true
            }
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(Color.black),
            size: size,
            settle: .turns(20)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("halloween is on."), "\(copy)")
            #expect(copy.contains("29 days left"), "\(copy)")
            #expect(copy.contains("4 of 15 earned. climb for the rest."), "\(copy)")
            #expect(catalog.showcase(of: event).map(\.shape) == [.pumpkinClassic, .witchHat, .pumpkinLantern], "items you can earn, not the athlete")
            try screen.photograph(named: "halloween-home-card")
            try activateAccessibilityElement(in: screen.root) { $0.accessibilityLabel?.hasPrefix("Halloween is on.") == true }
            #expect(opened, "the whole card opens the October page")
        }
    }

    // MARK: - The October page

    /// Every item on its ladder, with the state the climber's climbs give it. Hosted wide so each
    /// ladder's whole row is on screen to read.
    @Test
    func theOctoberPageShowsEveryItemOnItsLadder() async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        let event = try #require(unlocks.catalog.event(id: "halloween-2026"))
        let size = CGSize(width: 1_500, height: 1_300)
        try await RenderedScreen.host(
            NavigationStack {
                UnlockEventPage(event: event, unlocks: unlocks, looks: Self.looks(wearing: .pumpkinClassic), userId: { Self.userId }) {}
            }
            .modelContainer(container)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let tiles = try await Self.values(on: screen) { $0["Witching Hour Shorts"] != nil && $0["Midnight Pumpkin"] == "Earned" }
            #expect(tiles["Pumpkin"] == "Earned, on your athlete", "\(tiles)")
            for earned in ["Ghost Pumpkin", "Witch Hat", "Chocolate Bar", "Midnight Pumpkin"] {
                #expect(tiles[earned] == "Earned", "\(earned): \(tiles)")
            }
            #expect(tiles["Heirloom Pumpkin"] == "Next, 5 climbs", "\(tiles)")
            #expect(tiles["The Giant"] == "Next, 50K steps", "\(tiles)")
            #expect(tiles["Witching Hour Shorts"] == "Next, 7 days", "the day-based items sit on a third ladder: \(tiles)")
            #expect(tiles["Pumpkin Head"] == "Locked, Every day", "\(tiles)")
            #expect(tiles["Giant Jack-o'-Lantern"] == "Locked, 100K steps", "\(tiles)")

            let copy = try await screen.copy()
            for line in ["halloween is on.", "every climb and every step in october earns something new.",
                         "climbs in october", "steps in october", "days in october", "your athlete", "5 earned", "start climbing"] {
                #expect(copy.contains(line), "\(line): \(copy)")
            }
            for gone in ["how it works", "for showing up", "october on ascend mountain", "core", " of 38"] {
                #expect(!copy.contains(gone), "\(gone) is gone from the page: \(copy)")
            }
        }
    }

    /// The page at a phone's width, top and scrolled, for the photographs.
    @Test
    func theOctoberPageAtPhoneWidth() async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        let event = try #require(unlocks.catalog.event(id: "halloween-2026"))
        let size = CGSize(width: 402, height: 874)
        try await RenderedScreen.host(
            NavigationStack {
                UnlockEventPage(event: event, unlocks: unlocks, looks: Self.looks(wearing: .pumpkinClassic), userId: { Self.userId }) {}
            }
            .modelContainer(container)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("5 earned") || $0.contains("climbs in october") }
            #expect(copy.contains("days left") || copy.contains("last day"), "\(copy)")
            try screen.photograph(named: "halloween-october-page")
        }
        let tall = CGSize(width: 402, height: 1_250)
        try await RenderedScreen.host(
            NavigationStack {
                UnlockEventPage(event: event, unlocks: unlocks, looks: Self.looks(wearing: .pumpkinClassic), userId: { Self.userId }) {}
            }
            .modelContainer(container)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .frame(width: tall.width, height: tall.height),
            size: tall,
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy { $0.contains("5 earned") }
            try screen.photograph(named: "halloween-october-page-whole")
        }
    }

    // MARK: - The item view

    /// An earned item on the whole athlete, EQUIP, then the banner and EQUIPPED.
    @Test
    func equippingAnEarnedItemPutsItOnTheAthlete() async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        let event = try #require(unlocks.catalog.event(id: "halloween-2026"))
        let progress = try #require(unlocks.refresh(userId: Self.userId, modelContext: container.mainContext).first)
        let item = try #require(unlocks.catalog.items(earnedIn: event).first { $0.shape == .pumpkinMidnight })
        let looks = Self.looks(wearing: .pumpkinClassic)
        let size = CGSize(width: 402, height: 874)
        try await RenderedScreen.host(
            UnlockItemView(item: item, event: event, progress: progress, unlocks: unlocks, looks: looks, userId: { Self.userId }) {}
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(60)
        ) { screen in
            let copy = try await screen.copy { $0.contains("equip") }
            for line in ["halloween", "carried on your shoulder", "midnight pumpkin", "25k steps in october", "earned in october", "open your athlete", "equip"] {
                #expect(copy.contains(line), "\(line): \(copy)")
            }
            #expect(!copy.contains("locked"), "\(copy)")
            try screen.photograph(named: "halloween-item-earned-equip")

            try activateAccessibilityElement(labelled: "EQUIP", in: screen.root)
            // The banner shows for a couple of seconds: photograph it the moment it arrives.
            let banner = try await screen.text(containing: "Everyone on the stairs sees it.", reading: 400)
            #expect(banner != nil, "the banner says everyone on the stairs sees it")
            // Past its slide in, before it slides away.
            try await Task.sleep(for: .milliseconds(700))
            try screen.photograph(named: "halloween-item-equipped-banner")
            let after = try await screen.copy(reading: 400) { $0.contains("midnight pumpkin equipped") || $0.contains("equipped") }
            #expect(after.contains("equipped"), "\(after)")
            #expect(looks.current.wearing(.carry) == .pumpkinMidnight, "EQUIP puts it on the athlete in place of the Pumpkin")
        }
    }

    /// A locked giant on the whole athlete, pressed overhead, with how far there is to go.
    @Test(arguments: [AthleteGear.pumpkinGiant, .pumpkinGiantLantern])
    func aLockedGiantIsShownOverheadWithWhatItTakes(gear: AthleteGear) async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        let event = try #require(unlocks.catalog.event(id: "halloween-2026"))
        let progress = try #require(unlocks.refresh(userId: Self.userId, modelContext: container.mainContext).first)
        let item = try #require(unlocks.catalog.items(earnedIn: event).first { $0.shape == gear })
        let need = item.earn.threshold
        let size = CGSize(width: 402, height: 874)
        try await RenderedScreen.host(
            UnlockItemView(item: item, event: event, progress: progress, unlocks: unlocks, looks: Self.looks(wearing: nil), userId: { Self.userId }) {}
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(80)
        ) { screen in
            let copy = try await screen.copy { $0.contains("start climbing") }
            for line in ["held over your head", gear.title.lowercased(), "locked",
                         "25,000 of \(need.formatted()) steps", "\((need - 25_000).formatted()) to go", "start climbing"] {
                #expect(copy.contains(line), "\(line): \(copy)")
            }
            #expect(!copy.contains("earned in october"), "\(copy)")
            try screen.photograph(named: "halloween-item-locked-\(gear.rawValue)")
        }
    }

    // MARK: - Your Athlete

    /// The gear rows inside Your Athlete: what is owned, NEW on what has not been looked at, an
    /// earned item put on the athlete straight away, and a locked one opening what it takes.
    @Test
    func yourAthleteHoldsTheGearAndTriesItOn() async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        let looks = Self.looks(wearing: .pumpkinClassic)
        let size = CGSize(width: 402, height: 1_400)
        try await RenderedScreen.host(
            AthleteEditorView(store: looks, unlocks: unlocks, userId: { Self.userId })
                .modelContainer(container)
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(60)
        ) { screen in
            let cells = try await Self.values(on: screen) { $0["Ghost Pumpkin"] != nil && $0["Pumpkin"] == "On your athlete" }
            #expect(cells["Pumpkin"] == "On your athlete", "\(cells)")
            #expect(cells["Ghost Pumpkin"] == "Earned, new", "an earned item not looked at yet reads NEW: \(cells)")
            #expect(cells["Heirloom Pumpkin"] == "Locked", "\(cells)")
            let copy = try await screen.copy()
            for line in ["carried", "head", "kit", "feet", "4 owned", "1 owned", "save athlete", "body", "skin"] {
                #expect(copy.contains(line), "\(line): \(copy)")
            }
            for gone in ["marks", "trail", "open the locker", "wear what you earned"] {
                #expect(!copy.contains(gone), "\(gone): \(copy)")
            }
            try screen.photograph(named: "halloween-your-athlete-gear")

            try activateAccessibilityElement(labelled: "Ghost Pumpkin", in: screen.root)
            let tried = try await Self.values(on: screen) { $0["Ghost Pumpkin"] == "On your athlete" }
            #expect(tried["Pumpkin"]?.hasPrefix("Earned") == true, "ON moves to the item tapped: \(tried)")
            #expect(!unlocks.newItems.contains(.pumpkinGhost), "looking at it clears NEW")
            #expect(looks.current.wearing(.carry) == .pumpkinClassic, "nothing is kept until SAVE ATHLETE")
            try screen.photograph(named: "halloween-your-athlete-try-on")

            try activateAccessibilityElement(labelled: "The Giant", in: screen.root)
            let line = try await screen.copy { $0.contains("50k steps in october") }
            #expect(line.contains("50k steps in october · 25,000 of 50,000 steps"), "\(line)")
            #expect(tried["The Giant"] == "Locked")
            try screen.photograph(named: "halloween-your-athlete-locked-line")
        }
    }

    /// The Your Athlete card on Profile counts what is waiting to be looked at.
    @Test
    func theProfileCardCountsWhatIsNew() async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        unlocks.recordVisit(userId: Self.userId, now: try Self.october(5))
        unlocks.refresh(userId: Self.userId, modelContext: container.mainContext, now: try Self.october(5))
        unlocks.markSeen([.pumpkinClassic], userId: Self.userId)
        let size = CGSize(width: 402, height: 200)
        try await RenderedScreen.host(
            AthleteProfileCard(store: Self.looks(wearing: .pumpkinClassic), unlocks: unlocks, userId: { Self.userId })
                .padding(16)
                .modelContainer(container)
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                .frame(width: size.width, height: size.height)
                .background(Color.black),
            size: size,
            settle: .turns(40)
        ) { screen in
            let card = try await Self.values(on: screen) { $0["Your athlete"]?.contains("new to wear") == true }
            #expect(card["Your athlete"]?.hasSuffix("4 new to wear.") == true, "\(card)")
            let copy = try await screen.copy()
            #expect(copy.contains("4 new"), "\(copy)")
            try screen.photograph(named: "halloween-profile-card-new")
        }
    }

    // MARK: - The first open

    /// The build reaches a climber mid-October after three climbs on a build without unlocks. The
    /// first open credits all three, and the intro says what they already earned.
    @Test
    func climbsSavedBeforeTheUpdateCountOnTheFirstOpen() async throws {
        let container = try Self.threeEarlyOctoberClimbs()
        let unlocks = try Self.freshDevice(retiring: [])
        let firstOpen = try Self.october(5)
        unlocks.recordVisit(userId: Self.userId, now: firstOpen)
        let progress = try #require(unlocks.refresh(userId: Self.userId, modelContext: container.mainContext, now: firstOpen).first)
        #expect(progress.climbs == 3)
        #expect(progress.steps == 25_000)
        #expect(progress.days == 3)
        #expect(unlocks.earned == [.pumpkinClassic, .pumpkinGhost, .witchHat, .chocolateBar, .pumpkinMidnight], "\(unlocks.earned)")

        let event = try #require(unlocks.catalog.event(id: "halloween-2026"))
        var carried: AthleteGear?
        let size = CGSize(width: 402, height: 2_000)
        try await RenderedScreen.host(
            UnlockEventIntroView(event: event, items: unlocks.catalog.items(earnedIn: event), look: .starting(for: .man),
                                 earned: unlocks.earned, onCarry: { carried = $0 }, onClose: {})
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("already earned") }
            for line in ["halloween is on.", "every climb and every step in october earns something new.", "your pumpkin is in",
                         "your october climbs already earned 4 more", "put them on in your athlete", "climb in october to earn more", "yours to keep"] {
                #expect(copy.contains(line), "\(line): \(copy)")
            }
            for title in ["Ghost Pumpkin", "The Giant", "Giant Jack-o'-Lantern", "Ember Trainers"] {
                #expect(copy.contains(title.lowercased()), "the ladder lists \(title): \(copy)")
            }
            #expect(!copy.contains("october on ascend mountain"), "\(copy)")
            #expect(copy.contains("50k steps"), "thresholds read as bare counts: \(copy)")
            try screen.photograph(named: "halloween-first-open-intro")
            try activateAccessibilityElement(labelled: "EQUIP ON YOUR ATHLETE", in: screen.root)
            #expect(carried == .pumpkinClassic)
        }
    }

    // MARK: - Retired items

    /// The Giant retired on October 20: a climber who passes 50,000 steps only after that day
    /// never gets it, and one who passed it before keeps it in Your Athlete on a fresh phone.
    @Test(arguments: [false, true])
    func aRetiredItemIsKeptOnlyByThoseWhoEarnedItBeforeItRetired(earnedBeforeRetiring: Bool) async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        let climbs: [(day: Int, steps: Int)] = earnedBeforeRetiring ? [(5, 30_000), (19, 25_000)] : [(5, 40_000), (25, 20_000)]
        for climb in climbs {
            container.mainContext.insert(Workout(date: try Self.october(climb.day), duration: 3_600, steps: climb.steps, floors: 2_000, source: .headphoneMotion))
        }
        try container.mainContext.save()

        let unlocks = try Self.freshDevice(retiring: [(.pumpkinGiant, UnlockEvent.Day(year: 2026, month: 10, day: 20))])
        let size = CGSize(width: 1_500, height: 1_400)
        try await RenderedScreen.host(
            AthleteEditorView(store: Self.looks(wearing: nil), unlocks: unlocks, userId: { Self.userId })
                .modelContainer(container)
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(60)
        ) { screen in
            let cells = try await Self.values(on: screen) { $0["Midnight Pumpkin"] != nil }
            if earnedBeforeRetiring {
                #expect(cells["The Giant"]?.hasPrefix("Earned") == true, "passed 50,000 steps on October 19, before it retired: \(cells)")
                #expect(unlocks.earned.contains(.pumpkinGiant))
            } else {
                #expect(cells["The Giant"] == nil, "50,000 steps passed only on October 25, after it retired: \(cells)")
                #expect(!unlocks.earned.contains(.pumpkinGiant))
            }
            #expect(cells["Midnight Pumpkin"]?.hasPrefix("Earned") == true, "a live item is still earned as before: \(cells)")
        }
    }

    /// A retired item the climber is wearing stays in Your Athlete, so it can be taken off, even
    /// when nothing on this device remembers earning it.
    @Test
    func aWornRetiredItemStaysToBeTakenOff() async throws {
        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self)
        container.mainContext.insert(Workout(date: try Self.october(15), duration: 1_500, steps: 6_000, floors: 300, source: .headphoneMotion))
        try container.mainContext.save()

        let unlocks = try Self.freshDevice(retiring: [(.pumpkinGiantLantern, nil)])
        let size = CGSize(width: 1_500, height: 1_400)
        try await RenderedScreen.host(
            AthleteEditorView(store: Self.looks(wearing: .pumpkinGiantLantern), unlocks: unlocks, userId: { Self.userId })
                .modelContainer(container)
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(60)
        ) { screen in
            let title = AthleteGear.pumpkinGiantLantern.title
            let cells = try await Self.values(on: screen) { $0[title] == "On your athlete" }
            #expect(cells[title] == "On your athlete", "the worn retired item is offered so it can come off: \(cells)")
            #expect(!unlocks.earned.contains(.pumpkinGiantLantern))
        }
    }

    // MARK: - The finish summary

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

    // MARK: - Helpers

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
        return AthleteLookStore(repository: SavedLook(look: look), genderSource: { _ in .man }, defaults: UserDefaults(suiteName: "UnlockSurfaces-\(UUID().uuidString)")!)
    }

    /// Every labelled element on screen with what its value says, by label.
    private static func values(on screen: HostedScreen, until isReady: @escaping ([String: String]) -> Bool) async throws -> [String: String] {
        func read(_ elements: [NSObject]) -> [String: String] {
            Dictionary(elements.compactMap { element in
                guard let label = element.accessibilityLabel, let value = element.accessibilityValue, !value.isEmpty else { return nil }
                return (label, value)
            }, uniquingKeysWith: { first, _ in first })
        }
        let elements = try await screen.elements(reading: 400) { isReady(read($0)) }
        return read(elements)
    }

    private struct FixedCatalog: UnlockCatalogRepository {
        let catalog: UnlockCatalog
        func loadInitialCatalog() -> UnlockCatalog { catalog }
        func refreshCatalog() async throws -> UnlockCatalog { catalog }
    }

    private final class SavedLook: AthleteLookRepository, @unchecked Sendable {
        private var look: AthleteLook?
        init(look: AthleteLook?) { self.look = look }
        func fetchLook(userId: String) async throws -> AthleteLook? { look }
        func saveLook(_ look: AthleteLook, userId: String) async throws { self.look = look }
    }
}
