import SwiftUI

/// The monthly calendar sticker: the month's grid with the days that had a climb filled.
struct StickerCalendarContent: View {
    private static let gridWidth: CGFloat = 126
    private static let gap: CGFloat = 3
    private static let columns = 7
    private static let cellHeight: CGFloat = 15
    private static let cellWidth: CGFloat = (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)

    private let totals: ShareTotalsSnapshot
    private let weeks: [[Int?]]
    let ink: StickerInk

    init(totals: ShareTotalsSnapshot, ink: StickerInk) {
        self.totals = totals
        self.ink = ink
        weeks = Self.makeWeeks(leadingBlanks: totals.calendarLeadingBlanks, dayCount: totals.calendarDayCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ink.text(totals.calendarMonthName.uppercased(), size: 8, trackingEm: 0.16)
                Spacer(minLength: 0)
                ink.text(climbsText, size: 8, trackingEm: 0.16)
            }
            .frame(width: Self.gridWidth)
            Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
                ForEach(weeks.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<Self.columns, id: \.self) { column in
                            cell(weeks[row][column])
                        }
                    }
                }
            }
        }
    }

    private var climbsText: String {
        "\(totals.calendarClimbCount) \(totals.calendarClimbCount == 1 ? "CLIMB" : "CLIMBS")"
    }

    @ViewBuilder
    private func cell(_ day: Int?) -> some View {
        if let day {
            let climbed = totals.calendarClimbDays.contains(day)
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(climbed ? ink.color : Color.clear)
                ink.numeral("\(day)", size: 7, color: climbed ? ink.filledCellTextColor : ink.color)
            }
            .opacity(climbed ? 1 : 0.55)
            .frame(width: Self.cellWidth, height: Self.cellHeight)
        } else {
            Color.clear.frame(width: Self.cellWidth, height: Self.cellHeight)
        }
    }

    /// Monday-first rows of seven, empty cells before day 1 and after the last day.
    static func makeWeeks(leadingBlanks: Int, dayCount: Int) -> [[Int?]] {
        let blanks = Array(repeating: Int?.none, count: max(leadingBlanks, 0))
        let days = (1...max(dayCount, 1)).map { Int?.some($0) }
        var cells = blanks + (dayCount > 0 ? days : [])
        let remainder = cells.count % columns
        if remainder != 0 {
            cells += Array(repeating: Int?.none, count: columns - remainder)
        }
        return stride(from: 0, to: cells.count, by: columns).map { Array(cells[$0..<$0 + columns]) }
    }
}
