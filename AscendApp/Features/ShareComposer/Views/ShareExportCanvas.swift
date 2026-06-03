import SwiftUI

/// Static (gesture-free) render of the composed share, used by `ImageRenderer`
/// at export resolution. Mirrors the editing canvas exactly — same normalized
/// positions and the same proportional `canvasScale` — so output is WYSIWYG.
struct ShareExportCanvas: View {
    let viewModel: ShareComposerViewModel
    let size: CGSize
    /// Poster frame substituted for a video background at export time.
    var backgroundOverride: UIImage?
    /// When true, render only the stickers + wordmark on a transparent canvas
    /// (used as the overlay composited onto a video).
    var overlayOnly: Bool = false

    var body: some View {
        let canvasScale = size.width / 390

        ZStack {
            if !overlayOnly {
                Color.black
                backgroundLayer
            }

            ForEach(viewModel.stickers) { sticker in
                if sticker.isImage || !viewModel.resolvedStats(for: sticker).isEmpty {
                    ShareStickerVisual(
                        instance: sticker,
                        stats: viewModel.resolvedStats(for: sticker),
                        climb: viewModel.climb
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
        // Same pan/zoom as the editing canvas (offset is a canvas fraction, so it
        // maps to the export size). The outer ZStack clip trims any overflow.
        let scale = viewModel.backgroundScale
        let offX = viewModel.backgroundOffset.width * size.width
        let offY = viewModel.backgroundOffset.height * size.height

        if let backgroundOverride {
            Image(uiImage: backgroundOverride)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .shareBackgroundFilter(viewModel.backgroundFilter)
                .scaleEffect(scale)
                .offset(x: offX, y: offY)
        } else if let background = viewModel.background {
            ShareBackgroundView(
                source: background,
                isStatic: true,
                filter: viewModel.backgroundFilter,
                processedImage: viewModel.processedBackgroundImage
            )
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(x: offX, y: offY)
        } else {
            Color.black
        }
    }
}
