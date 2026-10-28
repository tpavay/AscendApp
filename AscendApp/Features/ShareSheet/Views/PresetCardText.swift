import SwiftUI

extension PresetFont {
    /// The card's text in design points. Fixed size on purpose: a card is an image, so it must not
    /// scale with the reader's Dynamic Type or one template would render differently per person.
    func cardFont(size: CGFloat, weight: Int) -> Font {
        .custom(postScriptName(weight: weight), fixedSize: size)
    }
}

extension View {
    /// Card text: the chosen face at a CSS-style weight, with tracking given in em as the design does.
    func presetText(
        _ font: PresetFont,
        size: CGFloat,
        weight: Int,
        trackingEm: CGFloat = 0,
        color: Color
    ) -> some View {
        self
            .font(font.cardFont(size: size, weight: weight))
            .tracking(trackingEm * size + CGFloat(font.tracking) * size)
            .foregroundStyle(color)
    }
}
