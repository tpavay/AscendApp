import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence that the October unlock surfaces a climber meets read the way the catalogue says:
/// the first-open intro gives the Pumpkin for opening Ascend and lists what climbing earns, and
/// the Locker shows a climb's earnings ready to wear and the rest locked with what earns them.
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
            try screen.photograph(named: "unlock-locker-carry-earned")
        }
    }

    private struct NoSavedLook: AthleteLookRepository {
        func fetchLook(userId: String) async throws -> AthleteLook? { nil }
        func saveLook(_ look: AthleteLook, userId: String) async throws {}
    }
}
