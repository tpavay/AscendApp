import SwiftUI

/// The headphone-split stickers: the Splits chart and the Fastest split.
struct StickerSplitsContent: View {
    private enum Variant {
        case chart, fastest
    }

    private static let chartHeight: CGFloat = 56
    private static let shortestBar: CGFloat = 18
    private static let chartMaxWidth: CGFloat = 124
    private static let barGap: CGFloat = 4

    private let variant: Variant
    private let subject: ShareSheetSubject
    let ink: StickerInk

    init?(kind: StickerKind, subject: ShareSheetSubject, ink: StickerInk) {
        guard subject.hasSplits else { return nil }
        switch kind {
        case .splitsChart: variant = .chart
        case .fastestSplit: variant = .fastest
        default: return nil
        }
        self.subject = subject
        self.ink = ink
    }

    var body: some View {
        switch variant {
        case .chart: chart
        case .fastest: fastest
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            ink.text("SPLITS \u{00B7} SPM", size: 7, trackingEm: 0.16, opacity: 0.85)
            HStack(alignment: .bottom, spacing: Self.barGap) {
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ink.color)
                        .opacity(bar.isFastest ? 1 : 0.4)
                        .frame(width: barWidth, height: bar.height)
                }
            }
            .frame(height: Self.chartHeight, alignment: .bottom)
            ink.text(rangeText, size: 12)
        }
    }

    private struct Bar: Identifiable {
        let id: Int
        let height: CGFloat
        let isFastest: Bool
    }

    /// Heights run from the slowest split to the fastest across the chart's height. Evenly paced
    /// splits all draw at full height, with the first split marked fastest.
    private var bars: [Bar] {
        let rates = subject.splits.map(\.stepsPerMinute)
        let lowest = rates.min() ?? 0
        let highest = rates.max() ?? 0
        let span = highest - lowest
        let fastestIndex = rates.firstIndex(of: highest)
        return subject.splits.enumerated().map { index, split in
            let fraction = span > 0 ? CGFloat((split.stepsPerMinute - lowest) / span) : 1
            return Bar(
                id: index,
                height: Self.shortestBar + (Self.chartHeight - Self.shortestBar) * fraction,
                isFastest: index == fastestIndex
            )
        }
    }

    /// The design's 12 points for its seven splits, narrowing so a long climb stays one sticker wide.
    private var barWidth: CGFloat {
        let count = CGFloat(max(subject.splits.count, 1))
        let fit = (Self.chartMaxWidth - (count - 1) * Self.barGap) / count
        return min(12, max(3, fit))
    }

    private var rangeText: String {
        guard let first = subject.splits.first, let last = subject.splits.last else { return "" }
        return "\(first.stepsPerMinuteText) \u{2192} \(last.stepsPerMinuteText) SPM"
    }

    private var fastest: some View {
        VStack(spacing: 0) {
            ink.text("FASTEST SPLIT", size: 7, trackingEm: 0.2, opacity: 0.85)
            if let split = subject.fastestSplit {
                ink.text(split.stepsPerMinuteText, size: 40, trackingEm: -0.03, lineHeight: 0.95)
                    .padding(.top, 4)
                ink.text("SPM \u{00B7} SPLIT \(split.number)", size: 8, trackingEm: 0.2, opacity: 0.85)
                    .padding(.top, 3)
                ink.text("\(split.stepsText) steps in \(split.durationText)", size: 11)
                    .padding(.top, 6)
            }
        }
    }
}
