import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// What the swipe looks like held still, photographed through the real pager: the handoff's frames
/// 01 to 03. Accent cards are used so a card is bright against the black behind it.
@Suite(.serialized, .hostsAWindow)
@MainActor
struct PresetCardPagerEvidenceTests {
    private func model(layout: PresetLayout) -> PresetsViewModel {
        let defaults = UserDefaults(suiteName: "PresetCardPagerEvidenceTests.\(UUID().uuidString)")!
        let model = PresetsViewModel(
            subject: .fixture(rank: .init(position: 7, field: 64)),
            hasTower: false,
            store: PresetPreferencesStore(defaults: defaults)
        )
        model.selectBackground(.accent)
        model.select(layout: layout)
        return model
    }

    private func screen(layout: PresetLayout, heldAt drag: CGFloat) -> some View {
        PresetCardPager(model: model(layout: layout), heldAt: drag)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 60)
            .background(Color.black)
    }

    /// Whether the point is lime-bright, which only a card there can be.
    private func isCard(_ screen: HostedScreen, x: CGFloat, y: CGFloat = 215) throws -> Bool {
        try screen.withPixels { $0.color(at: CGPoint(x: x, y: y)).green > 60 }
    }

    @Test
    func atRestTheCentreCardHasANeighbourPeekingAtEachSide() async throws {
        try await RenderedScreen.host(screen(layout: .rank, heldAt: 0)) { screen in
            #expect(try isCard(screen, x: 195))
            #expect(try isCard(screen, x: 6), "no left neighbour peeks in")
            #expect(try isCard(screen, x: 396), "no right neighbour peeks in")
            try screen.photograph(named: "share-sheet-swipe-rest")
        }
    }

    @Test
    func heldHalfwayTowardTheNextCardTwoCardsShowAndNothingElse() async throws {
        try await RenderedScreen.host(screen(layout: .rank, heldAt: -PresetPagerGeometry.step / 2)) { screen in
            #expect(try isCard(screen, x: 60), "the card being left is not on the left")
            #expect(try isCard(screen, x: 330), "the next card is not coming in on the right")
            #expect(try !isCard(screen, x: 195), "the gap between the two cards is filled")
            try screen.photograph(named: "share-sheet-swipe-halfway-left")
        }
    }

    @Test
    func heldHalfwayTowardThePreviousCardTwoCardsShowAndNothingElse() async throws {
        try await RenderedScreen.host(screen(layout: .rank, heldAt: PresetPagerGeometry.step / 2)) { screen in
            #expect(try isCard(screen, x: 60), "the previous card is not coming in on the left")
            #expect(try isCard(screen, x: 330), "the card being left is not on the right")
            try screen.photograph(named: "share-sheet-swipe-halfway-right")
        }
    }

    @Test
    func pulledPastTheFirstCardTheEmptySideStaysEmpty() async throws {
        try await RenderedScreen.host(screen(layout: .classic, heldAt: 200)) { screen in
            // 200 points of finger is 90 of card, and the previous card does not exist.
            #expect(try !isCard(screen, x: 20), "something came in from the left of the first card")
            #expect(try isCard(screen, x: 200))
            try screen.photograph(named: "share-sheet-swipe-pull-past-first")
        }
    }

    @Test
    func pulledPastTheLastCardTheEmptySideStaysEmpty() async throws {
        let last = model(layout: .classic).layouts.last ?? .classic
        try await RenderedScreen.host(screen(layout: last, heldAt: -200)) { screen in
            #expect(try !isCard(screen, x: 370), "something came in from the right of the last card")
            #expect(try isCard(screen, x: 190))
            try screen.photograph(named: "share-sheet-swipe-pull-past-last")
        }
    }
}
