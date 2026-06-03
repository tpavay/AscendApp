import SwiftUI

/// Static (gesture-free) render of the composed share, used by `ImageRenderer`
/// at export resolution. Mirrors the editing canvas exactly — same normalized
/// positions and the same proportional `canvasScale` — so output is WYSIWYG.
struct ShareExportCanvas: View {
    let viewModel: ShareComposerViewModel
    let size: CGSize
    /// Poster frame substituted for a video background at export time.
    var backgroundOverride: UIImage?

    var body: some View {
        let canvasScale = size.width / 390

        ZStack {
            backgroundLayer

            ForEach(viewModel.stickers) { sticker in
                if let stat = viewModel.resolve(sticker.kind) {
                    ShareStatStickerContent(
                        stat: stat,
                        style: sticker.style,
                        font: sticker.font,
                        color: sticker.color,
                        textBackground: sticker.textBackground
                    )
                        .scaleEffect(sticker.scale * canvasScale)
                        .rotationEffect(.radians(sticker.rotationRadians))
                        .position(x: sticker.position.x * size.width,
                                  y: sticker.position.y * size.height)
                }
            }

            // Always-on Ascend wordmark burned into every shared image.
            VStack {
                Spacer()
                AscendWordmark(size: 13 * canvasScale, letterColor: .white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 4 * canvasScale, x: 0, y: 1)
                    .padding(.bottom, 28 * canvasScale)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let backgroundOverride {
            Image(uiImage: backgroundOverride)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else if let background = viewModel.background {
            ShareBackgroundView(source: background, isStatic: true)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Color.black
        }
    }
}
