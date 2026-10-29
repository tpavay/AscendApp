import SwiftUI

/// The 34 point headline of the Curve and Splits cards with its small lime caption: on one line
/// while the headline stays within 15% of its size, the caption under it once it would not.
/// Neither is ever cut off or wrapped, whatever the figures grow to.
struct PresetHeadlineLine: View {
    let model: PresetCardModel
    let headline: String
    let caption: String

    var body: some View {
        let palette = model.palette
        PresetBesideOrBelow(floor: 0.85) {
            Text(headline)
                .presetText(model.font, size: 34, weight: 900, trackingEm: -0.03, color: Color(share: palette.foreground))
                .presetOneLine()
                .frame(height: 34)
            Text(caption)
                .presetText(model.font, size: 10, weight: 800, trackingEm: 0.14, color: Color(share: palette.accentText))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
        }
    }
}
