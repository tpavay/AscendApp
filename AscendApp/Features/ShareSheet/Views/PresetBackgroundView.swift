import SwiftUI

/// What sits behind a Presets card, filling its 310 by 310 design space.
struct PresetBackgroundView: View {
    let model: PresetCardModel
    var artwork: PresetCardArtwork = .none

    var body: some View {
        let side = PresetCardView.designSize
        ZStack {
            Color(share: model.palette.base)
            content
        }
        .frame(width: side, height: side)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch model.background {
        case .flat(let flat):
            PresetFlatBackgroundView(flat: flat, model: model)
        case .tower:
            // Tower artwork is composed with its subject in the upper third, so the crop keeps
            // the top and gives up the bottom, which the scrim darkens anyway.
            if let image = artwork.tower {
                PresetImageBackground(image: image, focalY: 0.3, scrim: .tower)
            }
        case .photo:
            if let image = artwork.photo {
                PresetImageBackground(image: image, focalY: 0.5, scrim: .photo)
            }
        case .seasonal(let seasonal):
            SeasonalBackgroundArt(background: seasonal)
        }
    }
}
