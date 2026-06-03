import SwiftUI

/// The visual content of a sticker — either a stat (text) or the climb's
/// artwork (image). Shared by the editing canvas and the export renderer so
/// both produce identical output.
struct ShareStickerVisual: View {
    let instance: ShareStickerInstance
    /// Resolved metrics for text stickers (empty for image stickers; more than
    /// one for a composite sticker).
    let stats: [ResolvedShareStat]
    /// Climb for image stickers (nil for stat stickers).
    let climb: Climb?

    var body: some View {
        if let variant = instance.climbImageVariant, let climb {
            ShareClimbImageVisual(climb: climb, variant: variant)
        } else if stats.count > 1 {
            ShareCompositeStatContent(
                stats: stats,
                layout: instance.layout,
                font: instance.font,
                color: instance.color,
                textBackground: instance.textBackground
            )
        } else if let stat = stats.first {
            ShareStatStickerContent(
                stat: stat,
                style: instance.style,
                font: instance.font,
                color: instance.color,
                textBackground: instance.textBackground
            )
        }
    }
}

/// A climb's artwork rendered at sticker scale with rounded corners.
struct ShareClimbImageVisual: View {
    let climb: Climb
    let variant: ClimbImageVariant

    private var size: CGSize {
        switch variant {
        case .hero: return CGSize(width: 190, height: 120)
        case .card: return CGSize(width: 120, height: 165)
        case .thumb: return CGSize(width: 96, height: 128)
        }
    }

    var body: some View {
        ClimbArtworkView(climb: climb, variant: variant)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
            .fixedSize()
    }
}
