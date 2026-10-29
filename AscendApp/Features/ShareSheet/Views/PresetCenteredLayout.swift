import SwiftUI

/// Centered: the steps at 82 points in the middle of the card with the switched-on stats under it.
struct PresetCenteredLayout: View {
    let model: PresetCardModel

    var body: some View {
        let palette = model.palette
        VStack(spacing: 0) {
            Text(model.subject.stepsText)
                .presetText(model.font, size: 82, weight: 900, trackingEm: -0.05, color: Color(share: palette.foreground))
                .presetOneLine(floor: 0.4)
                .frame(height: 82 * 0.9)
            Text("STEPS")
                .presetText(model.font, size: 12, weight: 800, trackingEm: 0.3, color: Color(share: palette.accentText))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
                .padding(.top, 6)
            PresetStatRow(model: model, centered: true, ruled: false, valueSize: 15, labelSize: 8)
                .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
