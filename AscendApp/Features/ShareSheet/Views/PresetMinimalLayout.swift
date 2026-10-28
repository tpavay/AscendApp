import SwiftUI

/// Minimal: one line in the bottom-left corner.
struct PresetMinimalLayout: View {
    let model: PresetCardModel

    var body: some View {
        Text(model.minimalLine)
            .presetText(model.font, size: 15, weight: 800, trackingEm: -0.01, color: Color(share: model.palette.foreground))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
