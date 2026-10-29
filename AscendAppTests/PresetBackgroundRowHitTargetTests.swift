import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Every swatch in the Background panel is one whole tile to tap: at least 44 points each way, and
/// sharing no ground with the tile beside it. A swatch draws a zoomed corner of its pattern clipped
/// to a 46 point square, and a clip bounds only the drawing - so before this the overflow of a
/// zoomed tile sat over its neighbours and took their taps.
@Suite(.serialized, .hostsAWindow)
@MainActor
struct PresetBackgroundRowHitTargetTests {
    private func model() -> PresetsViewModel {
        let defaults = UserDefaults(suiteName: "PresetBackgroundRowHitTargetTests.\(UUID().uuidString)")!
        return PresetsViewModel(
            subject: .fixture(),
            hasTower: true,
            store: PresetPreferencesStore(defaults: defaults),
            clock: { Date(timeIntervalSince1970: 1_792_000_000) },
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func screen(_ model: PresetsViewModel) -> some View {
        PresetBackgroundRow(model: model, onChoosePhoto: {})
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 120)
    }

    /// The tiles on screen, left to right, with the frame each one answers taps in.
    private func tiles(_ screen: HostedScreen) async throws -> [(label: String, frame: CGRect)] {
        try await screen.elements { elements in
            elements.contains { ($0.accessibilityLabel ?? "").hasSuffix(" background") }
        }
        .compactMap { element -> (label: String, frame: CGRect)? in
            guard let label = element.accessibilityLabel,
                  label.hasSuffix(" background") || label == "Choose a photo background" else { return nil }
            return (label, element.accessibilityFrame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    @Test
    func everyTileIsAtLeast44PointsEachWay() async throws {
        try await RenderedScreen.host(screen(model())) { screen in
            let found = try await tiles(screen)
            #expect(found.count >= 5, "only \(found.count) tiles were on screen")
            for tile in found {
                #expect(tile.frame.width >= 44, "\(tile.label) is \(tile.frame.width) wide")
                #expect(tile.frame.height >= 44, "\(tile.label) is \(tile.frame.height) tall")
            }
        }
    }

    @Test
    func noTileSitsOverItsNeighbour() async throws {
        try await RenderedScreen.host(screen(model())) { screen in
            let found = try await tiles(screen)
            for (left, right) in zip(found, found.dropFirst()) {
                #expect(
                    left.frame.maxX <= right.frame.minX + 0.5,
                    "\(left.label) reaches \(left.frame.maxX), over \(right.label) from \(right.frame.minX)"
                )
            }
        }
    }

    @Test
    func theGapBetweenTwoTilesBelongsToOneOfThem() async throws {
        try await RenderedScreen.host(screen(model())) { screen in
            let found = try await tiles(screen)
            for (left, right) in zip(found, found.dropFirst()) {
                #expect(
                    right.frame.minX - left.frame.maxX <= 0.5,
                    "a dead strip of \(right.frame.minX - left.frame.maxX) points lies between \(left.label) and \(right.label)"
                )
            }
        }
    }
}
