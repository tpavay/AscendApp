import Foundation

/// One sticker's resolved data and the card tree built from it.
///
/// Built when the sticker's *content* changes and held after that. A gesture
/// frame reads it; it never rebuilds it, which is the difference between a drag
/// costing a dictionary lookup and a drag costing a full stat resolution per
/// sticker per frame.
struct ShareStickerContent: Equatable {
    var node: ShareCardNode
    var context: ShareCardRenderContext
    var signature: ShareStickerContentSignature

    /// True when the sticker has nothing to draw and should not be placed.
    var isEmpty: Bool { !node.resolves(in: context) }

    func matches(_ instance: ShareStickerInstance) -> Bool {
        signature == ShareStickerContentSignature(instance)
    }
}

/// The parts of a sticker that decide what is drawn.
///
/// Position, scale and rotation are deliberately absent: they are what a gesture
/// changes, and they must not invalidate the card tree.
struct ShareStickerContentSignature: Hashable {
    let kind: ShareStatStickerKind
    let injectedStatKey: String?
    let extraStats: [ShareStatRef]
    let labelPlacement: ShareCardLabelPlacement
    let layout: ShareStatLayout
    let font: ShareStickerFont
    let color: RGBAColor
    let textBackground: ShareTextBackground
    let climbImageVariant: ClimbImageVariant?
    let presetID: String?

    init(_ instance: ShareStickerInstance) {
        presetID = instance.presetID
        kind = instance.kind
        injectedStatKey = instance.injectedStatKey
        extraStats = instance.extraStats
        labelPlacement = instance.labelPlacement
        layout = instance.layout
        font = instance.font
        color = instance.color
        textBackground = instance.textBackground
        climbImageVariant = instance.climbImageVariant
    }
}
