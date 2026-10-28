import SwiftUI

/// One Presets card in its 310 by 310 design space. Everything inside is positioned in these
/// units; `PresetCardCanvas` scales the whole card to a screen or export size.
struct PresetCardView: View {
    static let designSize: CGFloat = 310
    static let cornerRadius: CGFloat = 22

    let model: PresetCardModel
    var artwork: PresetCardArtwork = .none

    var body: some View {
        ZStack(alignment: .topLeading) {
            PresetBackgroundView(model: model, artwork: artwork)
                .scaleEffect(model.background == .photo ? artwork.photoScale : 1)
                .offset(
                    x: model.background == .photo ? artwork.photoOffset.width * Self.designSize : 0,
                    y: model.background == .photo ? artwork.photoOffset.height * Self.designSize : 0
                )

            layout
                .frame(width: Self.designSize, height: Self.designSize)

            PresetCardTopRow(model: model)
        }
        .frame(width: Self.designSize, height: Self.designSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            // Black gets a hairline so the card does not vanish into a black sheet.
            if model.background == .flat(.black) {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color(shareHex: 0x262626), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.layout.title) preset on \(model.background.title) background")
    }

    @ViewBuilder
    private var layout: some View {
        switch model.layout {
        case .classic: PresetClassicLayout(model: model)
        case .rank: PresetRankLayout(model: model)
        case .curve: PresetCurveLayout(model: model)
        case .splits: PresetSplitsLayout(model: model)
        case .splitTable: PresetSplitTableLayout(model: model)
        case .centered: PresetCenteredLayout(model: model)
        case .grid: PresetGridLayout(model: model)
        case .stackRight: PresetStackRightLayout(model: model)
        case .minimal: PresetMinimalLayout(model: model)
        }
    }
}

/// Scales a design-space card to any size, so the screen preview and the 1080 export are the same
/// drawing.
struct PresetCardCanvas: View {
    let model: PresetCardModel
    var artwork: PresetCardArtwork = .none
    let size: CGFloat

    var body: some View {
        PresetCardView(model: model, artwork: artwork)
            .scaleEffect(size / PresetCardView.designSize, anchor: .topLeading)
            .frame(width: size, height: size, alignment: .topLeading)
    }
}
