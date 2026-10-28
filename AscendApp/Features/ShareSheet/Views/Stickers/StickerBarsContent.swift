import SwiftUI

/// The weekly-steps sticker: the last six weeks as bars, the current week at full opacity.
struct StickerBarsContent: View {
    private static let chartHeight: CGFloat = 54
    private static let barWidth: CGFloat = 14
    private static let shortestBar: CGFloat = 2

    private let totals: ShareTotalsSnapshot
    let ink: StickerInk

    init(totals: ShareTotalsSnapshot, ink: StickerInk) {
        self.totals = totals
        self.ink = ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ink.text("WEEKLY STEPS", size: 7, trackingEm: 0.16, opacity: 0.85)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ink.color)
                        .opacity(bar.isCurrent ? 1 : 0.45)
                        .frame(width: Self.barWidth, height: bar.height)
                }
            }
            .frame(height: Self.chartHeight, alignment: .bottom)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ink.text(currentWeekText, size: 13)
                ink.text("THIS WEEK", size: 7, trackingEm: 0.14)
            }
        }
    }

    private struct Bar: Identifiable {
        let id: Int
        let height: CGFloat
        let isCurrent: Bool
    }

    private var bars: [Bar] {
        let steps = totals.weeklySteps
        let tallest = CGFloat(max(steps.max() ?? 0, 1))
        return steps.enumerated().map { index, value in
            Bar(
                id: index,
                height: max(Self.shortestBar, CGFloat(value) / tallest * Self.chartHeight),
                isCurrent: index == steps.count - 1
            )
        }
    }

    private var currentWeekText: String {
        (totals.weeklySteps.last ?? 0).formatted(.number.grouping(.automatic))
    }
}
