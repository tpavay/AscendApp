import Foundation
import Testing
@testable import AscendApp

struct SeasonalStickerCatalogTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test
    func novemberOffersFiveStickersInBoardOrder() {
        #expect(
            SeasonalStickerCatalog.stickers(on: date(2026, 11, 14), calendar: calendar)
                == [.turkey, .leaves, .pie, .legDay, .preFeast]
        )
    }

    @Test
    func decemberOffersFiveStickersInBoardOrder() {
        #expect(
            SeasonalStickerCatalog.stickers(on: date(2026, 12, 25), calendar: calendar)
                == [.snowflake, .cocoa, .pine, .gift, .lights]
        )
    }

    @Test
    func newYearsOffersFourStickersInBoardOrder() {
        #expect(
            SeasonalStickerCatalog.stickers(on: date(2027, 1, 1), calendar: calendar)
                == [.newPR, .yearBurst, .firstClimb, .resolutions]
        )
    }

    @Test
    func octoberOffersThreeStickersInBoardOrder() {
        #expect(
            SeasonalStickerCatalog.stickers(on: date(2027, 10, 31), calendar: calendar)
                == [.ghostDuo, .ghostSolo, .spookySzn]
        )
    }

    @Test
    func outOfSeasonDatesOfferNone() {
        for month in 2...9 {
            #expect(SeasonalStickerCatalog.stickers(on: date(2027, month, 15), calendar: calendar).isEmpty)
        }
    }

    @Test
    func windowEdgesBelongToTheirOwnTheme() {
        #expect(SeasonalStickerCatalog.stickers(on: date(2026, 11, 30), calendar: calendar).count == 5)
        #expect(SeasonalStickerCatalog.stickers(on: date(2026, 12, 1), calendar: calendar).first == .snowflake)
        #expect(SeasonalStickerCatalog.stickers(on: date(2026, 12, 31), calendar: calendar).first == .snowflake)
        #expect(SeasonalStickerCatalog.stickers(on: date(2027, 1, 31), calendar: calendar).first == .newPR)
    }

    @Test
    func everyKindBelongsToTheThemeThatOffersIt() {
        for theme in SeasonalTheme.allCases {
            let kinds = SeasonalStickerKind.allCases.filter { $0.theme == theme }
            #expect(!kinds.isEmpty)
        }
        let total = SeasonalTheme.allCases.reduce(0) { sum, theme in
            sum + SeasonalStickerKind.allCases.filter { $0.theme == theme }.count
        }
        #expect(total == SeasonalStickerKind.allCases.count)
    }

    @Test
    func everyTileReadsItsOwnTitleToVoiceOver() {
        for kind in SeasonalStickerKind.allCases {
            #expect(kind.accessibilityLabel == "\(kind.title) sticker. Tap to copy, hold to save")
        }
    }
}
