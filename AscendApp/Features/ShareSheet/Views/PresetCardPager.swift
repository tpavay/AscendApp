import SwiftUI

/// The card with a dimmed neighbour peeking on each side. Swiping 40 points or tapping a peek
/// pages; there is no wrap-around, so the first layout shows no left peek and the last no right.
/// A chosen photograph is framed instead: pinch to scale, drag to reposition.
struct PresetCardPager: View {
    let model: PresetsViewModel

    @State private var liveScale: CGFloat = 1
    @State private var liveOffset: CGSize = .zero

    private let side = PresetCardView.designSize

    var body: some View {
        let card = model.cardModel
        let peek = Color(share: card.palette.base == .ink ? ShareColor(0x141414) : card.palette.base)
        ZStack {
            if model.layoutIndex > 0 {
                peekCard(peek, leading: true)
            }
            if model.layoutIndex < model.layouts.count - 1 {
                peekCard(peek, leading: false)
            }
            PresetCardCanvas(model: card, artwork: framedArtwork, size: side)
                // Masked here and not inside the card: the exporter renders the same canvas through
                // `ImageRenderer`, which cannot draw the marker's UIKit view.
                .sentryMasked()
                .shadow(color: .black.opacity(0.6), radius: 25, x: 0, y: 18)
                .gesture(framingGesture, including: card.background == .photo ? .all : .none)
                .gesture(pageGesture, including: card.background == .photo ? .none : .all)
        }
        .frame(height: side)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: model.currentLayout)
    }

    private func peekCard(_ color: Color, leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(shareHex: 0x222222), lineWidth: 1))
            .frame(width: 300, height: 282)
            .opacity(0.45)
            .offset(x: leading ? -(side / 2 + 134) : (side / 2 + 134), y: 0)
            .onTapGesture { model.swipe(by: leading ? -1 : 1) }
            .accessibilityLabel(leading ? "Previous layout" : "Next layout")
            .accessibilityAddTraits(.isButton)
    }

    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.width < -40 {
                    model.swipe(by: 1)
                } else if value.translation.width > 40 {
                    model.swipe(by: -1)
                }
            }
    }

    private var framingGesture: some Gesture {
        MagnifyGesture()
            .onChanged { liveScale = $0.magnification }
            .onEnded { value in
                model.frame(scale: model.artwork.photoScale * value.magnification, offset: model.artwork.photoOffset)
                liveScale = 1
            }
            .simultaneously(with:
                DragGesture()
                    .onChanged { liveOffset = CGSize(width: $0.translation.width / side, height: $0.translation.height / side) }
                    .onEnded { value in
                        let base = model.artwork.photoOffset
                        model.frame(
                            scale: model.artwork.photoScale,
                            offset: CGSize(width: base.width + value.translation.width / side, height: base.height + value.translation.height / side)
                        )
                        liveOffset = .zero
                    }
            )
    }

    /// The artwork with the in-flight pinch and drag applied, so framing follows the fingers.
    private var framedArtwork: PresetCardArtwork {
        var artwork = model.artwork
        artwork.frame(
            scale: artwork.photoScale * liveScale,
            offset: CGSize(
                width: artwork.photoOffset.width + liveOffset.width,
                height: artwork.photoOffset.height + liveOffset.height
            )
        )
        return artwork
    }
}
