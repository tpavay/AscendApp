import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// A sticker tile is a grid cell: it keeps its column's width whatever the sticker measures, and
/// the sticker sits clear of the copy badge in the tile's top-trailing corner.
@MainActor
@Suite(.hostsAWindow)
struct StickerTileFitTests {
    private static let gutter: CGFloat = 10
    private static let margin: CGFloat = 16

    private struct Grid: View {
        let items: [StickerItem]
        let totals: ShareTotalsSnapshot?

        var body: some View {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: StickerTileFitTests.gutter), GridItem(.flexible(), spacing: StickerTileFitTests.gutter)],
                spacing: StickerTileFitTests.gutter
            ) {
                ForEach(items) { item in
                    StickerTile(
                        item: item,
                        subject: .fixture(),
                        totals: totals,
                        style: StickerStyle(),
                        year: 2026,
                        isActive: false,
                        onCopy: {},
                        onSave: {}
                    )
                }
            }
            .padding(.horizontal, StickerTileFitTests.margin)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 60)
            .background(Color.black)
        }
    }

    @Test
    func theStripStickerStaysInsideItsColumn() async throws {
        let view = Grid(items: [.standard(.stack), .standard(.strip)], totals: nil)
        try await RenderedScreen.host(view) { screen in
            let width = screen.bounds.width
            let column = (width - Self.margin * 2 - Self.gutter) / 2
            let strip = try #require(try await screen.frame(ofElementLabelled: StickerKind.strip.accessibilityLabel))

            #expect(abs(strip.width - column) < 1, "the Strip tile is \(strip.width) pt in a \(column) pt column")
            #expect(strip.maxX <= width - Self.margin + 0.5, "the Strip tile spills past the grid margin: \(strip)")
            #expect(strip.minX >= Self.margin + column + Self.gutter - 0.5, "the Strip tile closes the gutter: \(strip)")
        }
    }

    @Test
    func theCopyBadgeNeverCoversTheCalendarHeader() async throws {
        let view = Grid(items: [.standard(.calendar)], totals: Self.totals)
        try await RenderedScreen.host(view) { screen in
            let tile = try #require(try await screen.frame(ofElementLabelled: StickerKind.calendar.accessibilityLabel))
            // The badge's row, minus the badge itself: white sticker ink there is copy the badge
            // sits beside or on top of.
            let band = CGRect(x: tile.minX + 1, y: tile.minY + 1, width: tile.width - 34, height: 30)
            let ink = try screen.withPixels { $0.count(in: band) { $0.isNearWhite } }
            #expect(ink == 0, "\(ink) pixels of sticker copy sit in the copy badge's row")
            try screen.photograph(named: "sticker-tile-calendar")
        }
    }

    private static let totals = ShareTotalsSnapshot(
        period: .month,
        periodCaption: "OCTOBER",
        steps: 5_004,
        durationSeconds: 3_770,
        floors: 313,
        climbs: 1,
        calendarMonthName: "October",
        calendarLeadingBlanks: 3,
        calendarDayCount: 31,
        calendarClimbDays: [28],
        calendarClimbCount: 1,
        weeklySteps: [],
        averagePace30Days: nil,
        weekDays: [],
        weekStanding: nil,
        monthStanding: nil,
        yearStanding: nil
    )
}
