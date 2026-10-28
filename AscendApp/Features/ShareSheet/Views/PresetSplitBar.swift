import SwiftUI

/// One column of the Splits card: the pace above, the bar, the split number below.
struct PresetSplitBar: View {
    let model: PresetCardModel
    let split: ShareSheetSubject.Split
    let barHeight: CGFloat
    let isFastest: Bool

    var body: some View {
        let palette = model.palette
        VStack(spacing: 4) {
            Text(split.stepsPerMinuteText)
                .presetText(
                    model.font,
                    size: 9,
                    weight: 800,
                    color: Color(share: isFastest ? palette.accentText : palette.secondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isFastest ? Color(share: palette.accentText) : Color(share: palette.foreground).opacity(0.32))
                .frame(height: barHeight)
            Text(split.number)
                .presetText(model.font, size: 8, weight: 700, color: Color(share: palette.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}
