import SwiftUI

/// One seasonal sticker illustration, drawn at the point size it was exported for. The artwork
/// keeps its own colours whatever Color the climber picked.
struct SeasonalStickerArt: View {
    /// The bundled pieces. Raw values are the image names in the `Seasonal` asset group.
    enum Piece: String {
        case turkey = "StickerTurkey"
        case leaves = "StickerLeaves"
        case pie = "StickerPie"
        case snowflake = "StickerSnowflake"
        case mug = "StickerMug"
        case pine = "StickerPine"
        case gift = "StickerGift"
        case lights = "StickerLights"
        case burst = "StickerBurst"
        case sparkles = "StickerSparkles"
        case ghostDuo = "StickerGhostDuo"
        case ghostSolo = "StickerGhostSolo"

        var assetName: String { "Seasonal/\(rawValue)" }

        /// The size in points of the 3x image.
        var size: CGSize {
            switch self {
            case .turkey: return CGSize(width: 96, height: 90)
            case .leaves: return CGSize(width: 96, height: 44)
            case .pie: return CGSize(width: 116, height: 87)
            case .snowflake: return CGSize(width: 44, height: 44)
            case .mug: return CGSize(width: 74, height: 74)
            case .pine: return CGSize(width: 56, height: 86)
            case .gift: return CGSize(width: 110, height: 96)
            case .lights: return CGSize(width: 120, height: 33)
            case .burst: return CGSize(width: 70, height: 70)
            case .sparkles: return CGSize(width: 60, height: 26)
            case .ghostDuo: return CGSize(width: 90, height: 66)
            case .ghostSolo: return CGSize(width: 62, height: 70)
            }
        }
    }

    let piece: Piece

    var body: some View {
        Image(decorative: piece.assetName)
            .resizable()
            .interpolation(.high)
            .frame(width: piece.size.width, height: piece.size.height)
    }
}
