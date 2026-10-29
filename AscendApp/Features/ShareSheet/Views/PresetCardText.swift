import SwiftUI

extension PresetFont {
    /// The card's text in design points. Fixed size on purpose: a card is an image, so it must not
    /// scale with the reader's Dynamic Type or one template would render differently per person.
    func cardFont(size: CGFloat, weight: Int) -> Font {
        .custom(postScriptName(weight: weight), fixedSize: size)
    }
}

extension PresetFont {
    /// One styled run of a larger `Text`, for a line that mixes sizes yet has to scale as one:
    /// the Rank card's `#` beside its number. Styled the way `presetText` styles a whole view.
    func run(_ string: String, size: CGFloat, weight: Int, trackingEm: CGFloat = 0, color: Color) -> Text {
        Text(string)
            .font(cardFont(size: size, weight: weight))
            .tracking(trackingEm * size + CGFloat(tracking) * size)
            .foregroundStyle(color)
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

    /// One line, always: past its width the text scales down to `floor` and only then truncates.
    /// A card's numbers use the low default so a figure is never cut off, labels a higher one.
    func presetOneLine(floor: CGFloat = PresetFitGeometry.valueFloor) -> some View {
        lineLimit(1).minimumScaleFactor(floor)
    }
}
