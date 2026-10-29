import SwiftUI

/// Split table: one row per split, the fastest in the accent. Without splits it falls back to the
/// Classic body.
struct PresetSplitTableLayout: View {
    let model: PresetCardModel

    private static let numberColumnWidth: CGFloat = 26
    /// Height left for rows under the label and header, in the 310 point card.
    private static let rowsBudget: CGFloat = 205
    private static let rowTextHeight: CGFloat = 16

    var body: some View {
        let splits = model.subject.splits
        if splits.isEmpty {
            PresetClassicLayout(model: model)
        } else {
            content(splits: splits)
        }
    }

    private func content(splits: [ShareSheetSubject.Split]) -> some View {
        let palette = model.palette
        let fastestID = model.subject.fastestSplit?.id
        let padding = Self.rowPadding(rowCount: splits.count)
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("\(model.label) · SPLITS")
                .presetText(model.font, size: 10, weight: 700, trackingEm: 0.2, color: Color(share: palette.secondary))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            header
                .padding(.top, 8)
            ForEach(splits) { split in
                row(split: split, isFastest: split.id == fastestID, padding: padding)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// Five points above and below a row, tightened only when a long climb would otherwise run up
    /// into the top row.
    static func rowPadding(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 5 }
        let fitting = (rowsBudget / CGFloat(rowCount) - rowTextHeight - 1) / 2
        return min(5, max(1.5, fitting))
    }

    private var header: some View {
        let palette = model.palette
        return HStack(spacing: 0) {
            Text("#").frame(width: Self.numberColumnWidth, alignment: .leading)
            Text("TIME").frame(maxWidth: .infinity, alignment: .leading)
            Text("STEPS").frame(maxWidth: .infinity, alignment: .leading)
            Text("SPM").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .presetText(model.font, size: 8, weight: 800, trackingEm: 0.14, color: Color(share: palette.secondary))
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) { hairline }
    }

    private func row(split: ShareSheetSubject.Split, isFastest: Bool, padding: CGFloat) -> some View {
        let palette = model.palette
        return HStack(spacing: 0) {
            Text(split.number).frame(width: Self.numberColumnWidth, alignment: .leading)
            Text(split.durationText).frame(maxWidth: .infinity, alignment: .leading)
            Text(split.stepsText).frame(maxWidth: .infinity, alignment: .leading)
            Text(split.stepsPerMinuteText).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .presetText(
            model.font,
            size: 13,
            weight: 800,
            color: Color(share: isFastest ? palette.accentText : palette.foreground)
        )
        .presetOneLine(floor: 0.5)
        .padding(.vertical, padding)
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(share: model.palette.rule))
            .frame(height: 1)
    }
}
