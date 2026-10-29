import SwiftUI

/// Splits: the fastest split's pace as the headline over one bar per split, tallest where the
/// climber was fastest. Without splits it falls back to the Classic body.
struct PresetSplitsLayout: View {
    let model: PresetCardModel

    private static let shortestBar: CGFloat = 26
    private static let barRange: CGFloat = 90

    var body: some View {
        let splits = model.subject.splits
        if let fastest = model.subject.fastestSplit, !splits.isEmpty {
            content(splits: splits, fastest: fastest)
        } else {
            PresetClassicLayout(model: model)
        }
    }

    private func content(splits: [ShareSheetSubject.Split], fastest: ShareSheetSubject.Split) -> some View {
        let palette = model.palette
        return VStack(alignment: .leading, spacing: 0) {
            Text(model.label)
                .presetText(model.font, size: 10, weight: 700, trackingEm: 0.2, color: Color(share: palette.secondary))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            PresetHeadlineLine(model: model, headline: fastest.stepsPerMinuteText, caption: "SPM · FASTEST SPLIT")
                .padding(.top, 2)
            bars(splits: splits, fastest: fastest)
                .padding(.top, 8)
            footer(count: splits.count)
                .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bars(splits: [ShareSheetSubject.Split], fastest: ShareSheetSubject.Split) -> some View {
        let paces = splits.map(\.stepsPerMinute)
        let slowest = paces.min() ?? 0
        let quickest = paces.max() ?? 0
        return HStack(alignment: .bottom, spacing: splits.count > 12 ? 3 : 6) {
            ForEach(splits) { split in
                PresetSplitBar(
                    model: model,
                    split: split,
                    barHeight: Self.barHeight(pace: split.stepsPerMinute, slowest: slowest, quickest: quickest),
                    isFastest: split.id == fastest.id
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// 26 to 116 points by pace. Equal paces all draw the tallest bar, as in the design.
    static func barHeight(pace: Double, slowest: Double, quickest: Double) -> CGFloat {
        let ratio = quickest == slowest ? 1 : (pace - slowest) / (quickest - slowest)
        return (shortestBar + CGFloat(ratio) * barRange).rounded()
    }

    private func footer(count: Int) -> some View {
        let palette = model.palette
        return HStack(spacing: 0) {
            Text("\(count) SPLITS").presetOneLine(floor: 0.5)
            Spacer(minLength: 8)
            Text("\(model.subject.stepsText) STEPS").presetOneLine(floor: 0.5)
            Spacer(minLength: 8)
            Text(model.subject.durationText).presetOneLine(floor: 0.5)
        }
        .presetText(model.font, size: 10, weight: 800, trackingEm: 0.1, color: Color(share: palette.foreground))
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(share: palette.rule))
                .frame(height: 1)
        }
    }
}
