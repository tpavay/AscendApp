import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The Background panel's swatches draw the card's own background view, so what a tile shows is
/// what the card renders. With `ASCEND_EVIDENCE_DIR` set, the row is written out to look at.
@MainActor
struct PresetBackgroundSwatchTests {
    private let size: CGFloat = 46

    private func presets() -> PresetsViewModel {
        let defaults = UserDefaults(suiteName: "PresetBackgroundSwatchTests.\(UUID().uuidString)")!
        return PresetsViewModel(
            subject: .fixture(),
            hasTower: false,
            store: PresetPreferencesStore(defaults: defaults),
            clock: { Date(timeIntervalSince1970: 1_792_000_000) },
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func render<Content: View>(_ content: Content) throws -> UIImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = false
        return try #require(renderer.uiImage)
    }

    private func swatch(_ flat: PresetFlatBackground, in model: PresetsViewModel) throws -> ShareSheetExportTests.Pixels {
        try ShareSheetExportTests.Pixels(render(
            PresetBackgroundThumb(model: model.swatchModel(for: .flat(flat)), size: size)
        ))
    }

    /// The middle of a swatch, clear of its rounded corners and hairline.
    private var middle: CGRect {
        let inset = size * 3 * 0.2
        return CGRect(x: inset, y: inset, width: size * 3 - inset * 2, height: size * 3 - inset * 2)
    }

    @Test
    func theWholeCardSwatchesAreTheCardsOwnBackgroundShrunkToATile() throws {
        let model = presets()
        for flat in [PresetFlatBackground.glow, .fade, .aurora, .accent, .white] {
            let card = model.swatchModel(for: .flat(flat))
            let shrunk = try ShareSheetExportTests.Pixels(render(
                PresetBackgroundView(model: card)
                    .scaleEffect(size / PresetCardView.designSize, anchor: .topLeading)
                    .frame(width: size, height: size, alignment: .topLeading)
            ))
            let tile = try swatch(flat, in: model)
            var difference = 0
            var count = 0
            for y in Int(middle.minY)..<Int(middle.maxY) {
                for x in Int(middle.minX)..<Int(middle.maxX) {
                    for channel in 0..<3 {
                        difference += abs(tile.channel(channel, x: x, y: y) - shrunk.channel(channel, x: x, y: y))
                    }
                    count += 3
                }
            }
            #expect(Double(difference) / Double(count) < 2, "\(flat.title) swatch is not the card's background")
        }
    }

    @Test
    func thePatternAndGrainSwatchesShowTheirDetail() throws {
        let model = presets()
        let smooth = [PresetFlatBackground.glow, .fade, .aurora]
        let detailed = [PresetFlatBackground.hex, .stairs, .grid, .dots, .grain]
        let smoothest = try smooth.map { try swatch($0, in: model).edgeEnergy(in: middle) }.max() ?? 0
        for flat in detailed {
            let energy = try swatch(flat, in: model).edgeEnergy(in: middle)
            #expect(energy > smoothest + 0.3, "\(flat.title) swatch has no pattern (\(energy) against \(smoothest))")
        }
    }

    @Test
    func everyBackgroundDrawsASwatchAndTheRowIsKept() throws {
        let model = presets()
        let row = HStack(spacing: 8) {
            ForEach(PresetFlatBackground.allCases) { flat in
                PresetBackgroundThumb(model: model.swatchModel(for: .flat(flat)), size: size)
            }
        }
        .padding(12)
        .background(Color.black)
        let image = try render(row)
        if let directory = RenderedScreen.evidenceDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.pngData()?.write(to: directory.appending(path: "share-sheet-background-swatches.png"))
        }
        #expect(image.size.width > 0)
    }
}
