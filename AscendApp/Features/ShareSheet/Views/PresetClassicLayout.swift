import SwiftUI

/// Classic: label, the steps at 60 points with `STEPS` beside it, a hairline, then the switched-on
/// stats in a row.
struct PresetClassicLayout: View {
    let model: PresetCardModel

    var body: some View {
        let palette = model.palette
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(model.label)
                .presetText(model.font, size: 10, weight: 700, trackingEm: 0.2, color: Color(share: palette.secondary))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            PresetBesideOrBelow {
                Text(model.subject.stepsText)
                    .presetText(model.font, size: 60, weight: 900, trackingEm: -0.04, color: Color(share: palette.foreground))
                    .presetOneLine()
                Text("STEPS")
                    .presetText(model.font, size: 12, weight: 800, trackingEm: 0.14, color: Color(share: palette.accentText))
                    .presetOneLine(floor: PresetFitGeometry.labelFloor)
            }
            .padding(.top, 2)
            PresetStatRow(model: model)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
