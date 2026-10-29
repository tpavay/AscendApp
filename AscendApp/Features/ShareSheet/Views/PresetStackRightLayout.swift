import SwiftUI

/// Stack right: steps and up to three stats as a right-aligned column in the card's bottom-right
/// corner.
struct PresetStackRightLayout: View {
    let model: PresetCardModel

    var body: some View {
        let palette = model.palette
        VStack(alignment: .trailing, spacing: 10) {
            block(label: "STEPS", value: model.subject.stepsText, labelColor: palette.accentText)
            ForEach(model.gridStats) { item in
                block(label: item.label, value: item.value, labelColor: palette.secondary)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func block(label: String, value: String, labelColor: ShareColor) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label)
                .presetText(model.font, size: 9, weight: 700, trackingEm: 0.14, color: Color(share: labelColor))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            Text(value)
                .presetText(model.font, size: 26, weight: 900, trackingEm: -0.02, color: Color(share: model.palette.foreground))
                .presetOneLine()
                .frame(height: 26)
        }
    }
}
