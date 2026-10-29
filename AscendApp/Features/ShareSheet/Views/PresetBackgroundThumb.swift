import SwiftUI

/// A small swatch of a background for the bar and the panel's tiles. It draws the card's own
/// background view, so a swatch cannot drift from what the card renders: a pattern, a speck of
/// grain or a gradient changes in both places at once.
struct PresetBackgroundThumb: View {
    /// A model whose background is the one to show; the palette and accent come with it.
    let model: PresetCardModel
    var artwork: PresetCardArtwork = .none
    let size: CGFloat

    /// How much of the card a swatch shows. The gradients read whole at swatch size. The line and
    /// speck patterns do not: their 1 point strokes vanish when the whole card is shrunk to a
    /// tile, so a swatch shows the lit corner of the same drawing at a larger scale instead.
    private struct Window {
        /// 1 shows the whole card; 2.5 shows a 2.5th of its width.
        let zoom: CGFloat
        let anchor: UnitPoint
        let alignment: Alignment

        static let whole = Window(zoom: 1, anchor: .topLeading, alignment: .topLeading)
        /// The hex, grid and stairs patterns fade out from the top right, so that is the corner
        /// that holds the pattern.
        static let litCorner = Window(zoom: 2.5, anchor: .topTrailing, alignment: .topTrailing)
        static let middle = Window(zoom: 2.5, anchor: .center, alignment: .center)
    }

    private var window: Window {
        guard case .flat(let flat) = model.background else { return .whole }
        switch flat {
        case .hex, .grid, .stairs: return .litCorner
        case .dots, .grain: return .middle
        case .black, .white, .accent, .glow, .fade, .aurora: return .whole
        }
    }

    var body: some View {
        let window = window
        let corner = size * 0.22
        PresetBackgroundView(model: model, artwork: artwork)
            .scaleEffect(size * window.zoom / PresetCardView.designSize, anchor: window.anchor)
            .frame(width: size, height: size, alignment: window.alignment)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}
