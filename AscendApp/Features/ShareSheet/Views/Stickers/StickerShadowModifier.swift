import SwiftUI

/// The shadow choice from the sticker's style, drawn around the whole sticker.
///
/// Black stickers flip every shadow to white: a black shadow under black ink would vanish.
struct StickerShadowModifier: ViewModifier {
    let style: StickerStyle

    private var isDark: Bool { style.color == .black }
    private var edge: Color { isDark ? .white : .black }

    /// Four copies offset by one point each way: a stroke look that, unlike four chained
    /// `.shadow`s, does not compound into a two-point halo.
    private static let outlineOffsets: [CGSize] = [
        CGSize(width: -1, height: -1), CGSize(width: 1, height: -1),
        CGSize(width: -1, height: 1), CGSize(width: 1, height: 1)
    ]

    func body(content: Content) -> some View {
        switch style.shadow {
        case .none:
            content
        case .soft:
            // CSS blur is twice SwiftUI's radius, so the design's 12 and 10 become 6 and 5.
            content.shadow(
                color: edge.opacity(isDark ? 0.5 : 0.55),
                radius: isDark ? 5 : 6,
                x: 0,
                y: isDark ? 1 : 2
            )
        case .hard:
            content.shadow(color: edge.opacity(0.9), radius: 0, x: 2, y: 2)
        case .outline:
            ZStack {
                ForEach(Self.outlineOffsets, id: \.self) { offset in
                    silhouette(of: content).offset(offset)
                }
                content
            }
        }
    }

    /// The content flattened to one solid colour, alpha kept.
    @ViewBuilder
    private func silhouette(of content: Content) -> some View {
        if isDark {
            content.colorMultiply(.black).colorInvert()
        } else {
            content.colorMultiply(.black)
        }
    }
}

extension View {
    func stickerShadow(_ style: StickerStyle) -> some View {
        modifier(StickerShadowModifier(style: style))
    }
}
