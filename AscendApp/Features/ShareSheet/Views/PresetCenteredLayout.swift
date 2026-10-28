import SwiftUI

/// Centered: the steps at 82 points in the middle of the card with the switched-on stats under it.
struct PresetCenteredLayout: View {
    let model: PresetCardModel

    var body: some View {
        let palette = model.palette
        VStack(spacing: 0) {
            Text(model.subject.stepsText)
                .presetText(model.font, size: 82, weight: 900, trackingEm: -0.05, color: Color(share: palette.foreground))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 82 * 0.9)
            Text("STEPS")
                .presetText(model.font, size: 12, weight: 800, trackingEm: 0.3, color: Color(share: palette.accentText))
                .padding(.top, 6)
            HStack(alignment: .top, spacing: 22) {
                ForEach(model.stats) { item in
                    VStack(spacing: 0) {
                        Text(item.value)
                            .presetText(model.font, size: 15, weight: 800, color: Color(share: palette.foreground))
                        Text(item.label)
                            .presetText(model.font, size: 8, weight: 700, trackingEm: 0.12, color: Color(share: palette.secondary))
                    }
                }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
