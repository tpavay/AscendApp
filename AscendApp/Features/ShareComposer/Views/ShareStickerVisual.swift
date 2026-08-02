import SwiftUI
import UIKit

/// The visual content of a sticker.
///
/// A sticker is a small card: it is built into the same format a template is
/// written in and drawn by the same interpreter. Shared by the editing canvas
/// and the export renderer so both produce identical output.
struct ShareStickerVisual: View {
    let instance: ShareStickerInstance
    /// Pre-resolved data. Nothing is derived while this view renders.
    let content: ShareStickerContent
    let climb: Climb?
    /// Optional export-time image overrides for climb artwork stickers.
    var climbArtworkOverrides: [ClimbImageVariant: UIImage] = [:]

    var body: some View {
        ShareCardRenderer(
            node: content.node,
            context: content.context,
            artwork: ShareCardArtworkSource(climb: climb, overrides: climbArtworkOverrides)
        )
        .fixedSize()
    }
}

/// A climb's artwork at sticker size, for the add sheet's picker tiles.
/// Goes through the same builder and the same interpreter as a placed sticker,
/// so the tile shows exactly what the canvas will.
struct ShareClimbImageVisual: View {
    let climb: Climb
    let variant: ClimbImageVariant

    var body: some View {
        let instance = ShareStickerInstance(kind: .climbName, climbImageVariant: variant)
        ShareCardRenderer(
            node: ShareStickerCardBuilder.node(for: instance, resolvedRefs: []),
            context: ShareCardRenderContext(),
            artwork: ShareCardArtworkSource(climb: climb)
        )
        .fixedSize()
    }
}

