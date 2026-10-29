import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Renders what the share sheet exports, through the exporter's own `ImageRenderer` path. Cards
/// are square and rounded, stickers are transparent, and every one draws something. With
/// `ASCEND_EVIDENCE_DIR` set the images are written out for comparison against the design.
@MainActor
struct ShareSheetExportTests {
    private let exporter = ShareSheetExporter()

    private var calendar: Calendar {
        var calendar = WeekConfiguration.calendar(timeZone: TimeZone(identifier: "UTC")!)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func presets(
        subject: ShareSheetSubject = .fixture(bestEfforts: [ShareSheetSubject.effort("steps60", rank: 2)]),
        on day: Date
    ) -> PresetsViewModel {
        let defaults = UserDefaults(suiteName: "ShareSheetExportTests.\(UUID().uuidString)")!
        return PresetsViewModel(
            subject: subject,
            hasTower: false,
            store: PresetPreferencesStore(defaults: defaults),
            clock: { day },
            calendar: calendar
        )
    }

    private var totals: ShareTotalsSnapshot {
        let samples = (0..<12).map { index in
            ShareTotalsBuilder.Sample(
                date: calendar.date(byAdding: .day, value: -index * 2, to: date(10, 28))!,
                steps: 2_000 + index * 150,
                duration: 1_800
            )
        }
        let built = ShareTotalsBuilder.make(samples: samples, period: .month, now: date(10, 28), calendar: calendar)
        // The standings come from the server, so a built snapshot has none and the rank stickers
        // would draw only their wordmark.
        return ShareTotalsSnapshot(
            period: built.period,
            periodCaption: built.periodCaption,
            steps: built.steps,
            durationSeconds: built.durationSeconds,
            floors: built.floors,
            climbs: built.climbs,
            calendarMonthName: built.calendarMonthName,
            calendarLeadingBlanks: built.calendarLeadingBlanks,
            calendarDayCount: built.calendarDayCount,
            calendarClimbDays: built.calendarClimbDays,
            calendarClimbCount: built.calendarClimbCount,
            weeklySteps: built.weeklySteps,
            averagePace30Days: built.averagePace30Days,
            weekDays: built.weekDays,
            weekStanding: ShareTotalsSnapshot.Standing(position: 3, field: 120),
            monthStanding: ShareTotalsSnapshot.Standing(position: 8, field: 340),
            yearStanding: ShareTotalsSnapshot.Standing(position: 21, field: 900)
        )
    }

    // MARK: - Cards

    @Test
    func everyLayoutExportsASquareRoundedCardThatDrawsSomething() throws {
        let model = presets(on: date(10, 28))
        for layout in model.layouts {
            model.select(layout: layout)
            let image = try #require(exporter.renderCard(model: model.cardModel, artwork: model.artwork))
            try Self.expectCard(image, named: "card-\(layout.rawValue)")
            try Self.keep(image, named: "card-\(layout.rawValue)")
        }
    }

    @Test
    func everySeasonalBackgroundExportsACardInItsOwnWindow() throws {
        let windows: [(SeasonalTheme, Date)] = [
            (.october, date(10, 15)), (.november, date(11, 15)), (.december, date(12, 15)), (.newYear, date(1, 15))
        ]
        for (theme, day) in windows {
            let model = presets(on: day)
            let backgrounds = SeasonalBackground.available(on: day, calendar: calendar)
            #expect(!backgrounds.isEmpty, "\(theme) has no background in its window")
            for background in backgrounds {
                model.selectSeasonal(background)
                let image = try #require(exporter.renderCard(model: model.cardModel, artwork: model.artwork))
                try Self.expectCard(image, named: "seasonal-\(background.rawValue)")
                try Self.keep(image, named: "seasonal-\(background.rawValue)")
            }
        }
    }

    // MARK: - Story

    @Test
    func storyHandsInstagramTheCardAloneAsASticker() throws {
        for background in [PresetCardBackground.flat(.black), .flat(.aurora)] {
            let model = presets(on: date(10, 28))
            if case .flat(let flat) = background { model.selectBackground(flat) }
            let card = try #require(exporter.renderCard(model: model.cardModel, artwork: model.artwork))

            let items = try #require(exporter.instagramStoryItems(for: card))
            #expect(items.count == 1)
            let item = try #require(items.first)
            // Only the sticker key: a `backgroundImage` is what drew a dark rectangle behind the card.
            #expect(Set(item.keys) == [ShareSheetExporter.instagramStickerKey])

            let data = try #require(item[ShareSheetExporter.instagramStickerKey] as? Data)
            let sent = try #require(UIImage(data: data))
            let pixels = try Pixels(sent)
            #expect(pixels.width == 1080 && pixels.height == 1080, "the Story image is \(pixels.width)x\(pixels.height)")
            for corner in [(1, 1), (pixels.width - 2, 1), (1, pixels.height - 2), (pixels.width - 2, pixels.height - 2)] {
                #expect(pixels.alpha(x: corner.0, y: corner.1) == 0, "a Story corner is opaque")
            }
            #expect(pixels.alpha(x: 540, y: 540) == 255)
            try Self.keep(sent, named: "story-\(model.background.title.lowercased())")
        }
    }

    // MARK: - Stickers

    @Test
    func everyStickerExportsOnATransparentBackground() throws {
        let subject = ShareSheetSubject.fixture(bestEfforts: [ShareSheetSubject.effort("steps60", rank: 2)])
        let snapshot = totals
        for kind in StickerKind.allCases {
            let image = try #require(exporter.renderSticker(
                StickerView(kind: kind, subject: subject, totals: snapshot, style: StickerStyle())
            ))
            try Self.expectSticker(image, named: "sticker-\(kind.rawValue)")
            try Self.keep(image, named: "sticker-\(kind.rawValue)")
        }
    }

    @Test
    func everySeasonalStickerExportsOnATransparentBackground() throws {
        for kind in SeasonalStickerKind.allCases {
            let image = try #require(exporter.renderSticker(
                SeasonalStickerView(kind: kind, subject: .fixture(), style: StickerStyle(), year: 2026)
            ))
            try Self.expectSticker(image, named: "seasonal-sticker-\(kind.rawValue)")
            try Self.keep(image, named: "seasonal-sticker-\(kind.rawValue)")
        }
    }

    @Test
    func aBlackStickerStillDrawsInk() throws {
        let image = try #require(exporter.renderSticker(
            StickerView(
                kind: .stack,
                subject: .fixture(),
                totals: nil,
                style: StickerStyle(font: .bold, color: .black, shadow: .none)
            )
        ))
        try Self.expectSticker(image, named: "sticker-stack-black")
    }

    // MARK: - Pixels

    private static func expectCard(_ image: UIImage, named name: String) throws {
        let pixels = try Pixels(image)
        #expect(pixels.width == 1080 && pixels.height == 1080, "\(name) exported \(pixels.width)x\(pixels.height)")
        #expect(pixels.alpha(x: 1, y: 1) == 0, "\(name) has no rounded corner")
        #expect(pixels.alpha(x: 540, y: 540) == 255, "\(name) is not opaque in the middle")
        #expect(pixels.distinctColours(stride: 24) > 3, "\(name) is a flat fill")
    }

    private static func expectSticker(_ image: UIImage, named name: String) throws {
        let pixels = try Pixels(image)
        #expect(pixels.alpha(x: 0, y: 0) == 0, "\(name) has an opaque corner")
        #expect(pixels.alpha(x: pixels.width - 1, y: pixels.height - 1) == 0, "\(name) has an opaque corner")
        #expect(pixels.opaqueFraction(stride: 4) > 0.01, "\(name) draws nothing")
    }

    private static func keep(_ image: UIImage, named name: String) throws {
        guard let directory = RenderedScreen.evidenceDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.pngData()?.write(to: directory.appending(path: "share-sheet-\(name).png"))
    }

    struct Pixels {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try #require(image.cgImage)
            width = cgImage.width
            height = cgImage.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func alpha(x: Int, y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }

        func channel(_ channel: Int, x: Int, y: Int) -> Int { Int(bytes[(y * width + x) * 4 + channel]) }

        /// The mean step between neighbouring pixels inside `region`: near zero for a smooth
        /// gradient, high for a pattern or grain.
        func edgeEnergy(in region: CGRect) -> Double {
            var total = 0
            var count = 0
            for y in Int(region.minY)..<Int(region.maxY) {
                for x in Int(region.minX)..<Int(region.maxX) - 1 {
                    for channel in 0..<3 {
                        total += abs(self.channel(channel, x: x, y: y) - self.channel(channel, x: x + 1, y: y))
                    }
                    count += 3
                }
            }
            return Double(total) / Double(max(count, 1))
        }

        func distinctColours(stride step: Int) -> Int {
            var seen = Set<UInt32>()
            for y in Swift.stride(from: 0, to: height, by: step) {
                for x in Swift.stride(from: 0, to: width, by: step) {
                    let index = (y * width + x) * 4
                    // Quantised so antialiasing noise does not count as a colour.
                    seen.insert(UInt32(bytes[index] >> 4) << 8 | UInt32(bytes[index + 1] >> 4) << 4 | UInt32(bytes[index + 2] >> 4))
                }
            }
            return seen.count
        }

        func opaqueFraction(stride step: Int) -> Double {
            var opaque = 0
            var total = 0
            for y in Swift.stride(from: 0, to: height, by: step) {
                for x in Swift.stride(from: 0, to: width, by: step) {
                    total += 1
                    if alpha(x: x, y: y) > 16 { opaque += 1 }
                }
            }
            return Double(opaque) / Double(max(total, 1))
        }
    }
}
