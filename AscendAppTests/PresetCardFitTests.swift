import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// No figure on a Presets card wraps or ends in an ellipsis, on any layout and in any face, at the
/// largest values a climb can reach: a 100 hour time, a six digit rank in a seven digit pool,
/// thousands of floors. The card is read the way the Story and Save exports draw it
/// (`ImageRenderer` over `PresetCardCanvas`) and then through the Vision pass the Sentry mask
/// tests use, so a digit dropped to a second line or cut to `...` is a missing token.
@MainActor
struct PresetCardFitTests {
    struct Climb: CustomTestStringConvertible, Sendable {
        let name: String
        let steps: String
        let duration: String
        let pace: String
        let floors: String
        let heartRate: Int?
        let position: Int
        let field: Int
        var testDescription: String { name }
    }

    /// The captain's own example (four stats on the Classic card), then the extremes with every
    /// stat switched on at once.
    nonisolated static let climbs = [
        Climb(name: "1:30:07 and 806 of 914", steps: "5,004", duration: "1:30:07", pace: "85.5", floors: "482", heartRate: nil, position: 806, field: 914),
        Climb(name: "24:00:00 in a pool of thousands", steps: "115,200", duration: "24:00:00", pace: "123.4", floors: "12,345", heartRate: 188, position: 12_345, field: 98_765),
        Climb(name: "100:00:00 in a pool of millions", steps: "480,000", duration: "100:00:00", pace: "123.4", floors: "54,321", heartRate: 188, position: 123_456, field: 1_234_567),
        Climb(name: "100:00:00 in the lower half of millions", steps: "480,000", duration: "100:00:00", pace: "123.4", floors: "54,321", heartRate: 188, position: 987_654, field: 1_234_567),
        Climb(name: "on the line, 32nd of 64", steps: "5,004", duration: "1:02:50", pace: "79.6", floors: "313", heartRate: 127, position: 32, field: 64),
        Climb(name: "just under it, 33rd of 64", steps: "5,004", duration: "1:02:50", pace: "79.6", floors: "313", heartRate: 127, position: 33, field: 64),
        Climb(name: "first ascent, 1 of 1", steps: "5,004", duration: "1:02:50", pace: "79.6", floors: "313", heartRate: 127, position: 1, field: 1),
        Climb(name: "a pool of two, 1 of 2", steps: "5,004", duration: "1:02:50", pace: "79.6", floors: "313", heartRate: 127, position: 1, field: 2),
    ]

    nonisolated static let layouts: [PresetLayout] = [.classic, .rank, .curve, .splits, .centered, .grid, .stackRight, .minimal]

    private func card(_ climb: Climb, layout: PresetLayout, font: PresetFont) -> PresetCardModel {
        let defaults = UserDefaults(suiteName: "PresetCardFitTests.\(UUID().uuidString)")!
        let model = PresetsViewModel(
            subject: .fixture(
                stepsText: climb.steps,
                durationText: climb.duration,
                stepsPerMinuteText: climb.pace,
                floorsText: climb.floors,
                averageHeartRate: climb.heartRate,
                rank: .init(position: climb.position, field: climb.field)
            ),
            hasTower: false,
            store: PresetPreferencesStore(defaults: defaults)
        )
        for stat in model.availableStats where !model.preferences.isOn(stat) {
            model.toggle(stat)
        }
        model.setFont(font)
        model.select(layout: layout)
        return model.cardModel
    }

    /// Letters and digits only, with the look-alikes Vision swaps (`C` for `G`, `O` for `0`) folded
    /// together on both sides, so `1:30:07` and `#806` compare by their characters and not their
    /// punctuation. Spaces survive: a figure that wrapped is `1300 7` here, not `13007`.
    private func folded(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            if character.isWhitespace {
                if result.last != " " { result.append(" ") }
            } else if character.isLetter || character.isNumber {
                switch character {
                case "o": result.append("0")
                case "l", "i": result.append("1")
                case "s": result.append("5")
                case "b": result.append("8")
                case "g": result.append("c")
                case "\u{0440}": result.append("p")
                case "\u{0442}": result.append("t")
                default: result.append(character)
                }
            }
        }
        return result
    }

    /// Whether every word of `token` is in `seen` whole, give or take one misread character in a
    /// word of five or more (Vision turns a `3` into a `5` now and then). A word has to sit in one
    /// piece: `1:30:07` that dropped its `7` to a second line reads `1300 7` and fails, as does one
    /// cut to `1:30...`.
    private func reads(_ seen: String, _ token: String) -> Bool {
        let hay = Array(seen)
        return folded(token).split(separator: " ").allSatisfy { word in
            let pin = Array(word)
            let allowed = pin.count >= 5 ? 1 : 0
            guard hay.count >= pin.count else { return false }
            return (0...(hay.count - pin.count)).contains { start in
                let window = hay[start..<(start + pin.count)]
                return !window.contains(" ")
                    && zip(window, pin).filter { $0 != $1 }.count <= allowed
            }
        }
    }

    /// What this layout puts on the card, as strings that must come back whole.
    private func expected(_ model: PresetCardModel, layout: PresetLayout, climb: Climb) -> [String] {
        let subject = model.subject
        let rank = subject.rank
        let values = model.stats.map(\.value)
        switch layout {
        case .classic, .centered:
            // A label is only a token to keep when it carries a figure, like `RANK / 1,234,567`; at
            // the extremes the words beside it are legitimately small.
            return [subject.stepsText] + values + model.stats.map(\.label).filter { $0.contains(where: \.isNumber) }
        case .rank:
            let percentile = rank.map(\.percentileColumnValue)
            // A one or two digit rank has nothing to scale, and Vision is shaky on a short tracked-in word.
            return [rank.map(\.positionText).flatMap { $0.count >= 3 ? $0 : nil }, rank.map { "of \($0.fieldText)" }, percentile, subject.stepsText, subject.durationText]
                .compactMap { $0 }
        case .curve:
            return [rank?.headline, rank?.fieldCaption, rank?.beatCaption].compactMap { $0 }
        case .splits:
            return [subject.fastestSplit?.stepsPerMinuteText, "\(subject.stepsText) STEPS", subject.durationText].compactMap { $0 }
        case .grid, .stackRight:
            return [subject.stepsText] + model.gridStats.map(\.value)
        case .minimal:
            return [subject.stepsText] + model.stats.map(\.value)
        case .splitTable:
            return []
        }
    }

    private func read(_ model: PresetCardModel) async throws -> String {
        try await RenderedScreen.recognizedText(
            of: PresetCardCanvas(model: model, size: PresetCardView.designSize),
            scale: 6
        )
    }

    @Test(arguments: climbs, layouts)
    func everyFigureOnTheCardComesBackWhole(climb: Climb, layout: PresetLayout) async throws {
        let model = card(climb, layout: layout, font: .bold)
        let text = try await read(model)
        #expect(!text.contains("…") && !text.contains("..."), "\(layout.title) is truncated: \(text)")
        let seen = folded(text)
        for token in expected(model, layout: layout, climb: climb) {
            #expect(reads(seen, token), "\(layout.title) lost \(token): \(text)")
        }
    }

    @Test(arguments: PresetFont.allCases, layouts)
    func everyFaceKeepsTheWidestClimbWhole(font: PresetFont, layout: PresetLayout) async throws {
        let climb = Self.climbs[3]
        let model = card(climb, layout: layout, font: font)
        let text = try await read(model)
        #expect(!text.contains("…") && !text.contains("..."), "\(layout.title) in \(font.title) is truncated: \(text)")
        let seen = folded(text)
        for token in expected(model, layout: layout, climb: climb) {
            #expect(reads(seen, token), "\(layout.title) in \(font.title) lost \(token): \(text)")
        }
    }

    @Test
    func theMinimalLineBreaksOnlyAfterADot() {
        let model = card(Self.climbs[2], layout: .minimal, font: .bold)
        let line = PresetMinimalLayout.unbreakable(model.minimalLine)
        // Steps plus each stat is one more piece than there are separators, and a plain space, the
        // only place a line may break, follows exactly one dot each.
        #expect(line.filter { $0 == " " }.count == model.stats.count)
        #expect(line.components(separatedBy: " ").dropLast().allSatisfy { $0.hasSuffix("·") })
        for stat in model.stats {
            #expect(line.contains(PresetMinimalLayout.unbreakable(stat.inlineText)))
        }
    }

    @Test(arguments: [PresetLayout.classic, .rank, .curve])
    func theCardDrawsTheSameAtAnyTextSize(layout: PresetLayout) throws {
        // A card draws at one fixed type size, so what Story and Save export is what the preview
        // showed whatever Dynamic Type the climber runs.
        let model = card(Self.climbs[3], layout: layout, font: .bold)
        func png(_ size: DynamicTypeSize) throws -> Data {
            let renderer = ImageRenderer(
                content: PresetCardCanvas(model: model, size: PresetCardView.designSize)
                    .environment(\.dynamicTypeSize, size)
            )
            renderer.scale = 2
            return try #require(renderer.uiImage?.pngData())
        }
        #expect(try png(.large) == png(.large), "a render is not repeatable, so no comparison below means anything")
        #expect(try png(.large) == png(.accessibility5))
    }

    /// With `ASCEND_EVIDENCE_DIR` set, every layout at the captain's figures and at the extremes is
    /// written out to look at. CI sets nothing and this draws nothing.
    @Test
    func writesTheCardsForReview() throws {
        guard let directory = RenderedScreen.evidenceDirectory else { return }
        for (index, climb) in Self.climbs.enumerated() {
            for layout in Self.layouts {
                let renderer = ImageRenderer(
                    content: PresetCardCanvas(model: card(climb, layout: layout, font: .bold), size: PresetCardView.designSize)
                )
                renderer.scale = 3
                let data = try #require(renderer.uiImage?.pngData())
                try data.write(to: directory.appending(path: "share-fit-\(index)-\(layout.rawValue).png"))
            }
        }
    }
}
