import SwiftUI

/// An image aspect-filled into the card, with the CSS `object-position` focal point on the
/// vertical axis. Drawn as an overlay on `Color.clear` so a landscape photo that scales wider than
/// the card cannot widen the view that holds it.
struct PresetFilledImage: View {
    let image: UIImage
    /// 0 keeps the top of the picture, 1 the bottom, 0.5 centres it.
    var focalY: CGFloat = 0.5

    var body: some View {
        let side = PresetCardView.designSize
        let source = image.size
        let scale = (source.width > 0 && source.height > 0)
            ? max(side / source.width, side / source.height)
            : 1
        let width = source.width * scale
        let height = source.height * scale

        Color.clear
            .frame(width: side, height: side)
            .overlay(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: width, height: height)
                    .offset(x: -(width - side) / 2, y: -(height - side) * focalY)
            }
            .clipped()
    }
}
