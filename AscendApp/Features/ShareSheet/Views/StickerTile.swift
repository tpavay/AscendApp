import SwiftUI

/// One sticker on a checkerboard that shows its transparency. A tap copies and a hold of 0.55
/// seconds saves; the hold wins, so it never also copies.
struct StickerTile: View {
    let item: StickerItem
    let subject: ShareSheetSubject
    let totals: ShareTotalsSnapshot?
    let style: StickerStyle
    let year: Int
    let isActive: Bool
    let onCopy: () -> Void
    let onSave: () -> Void

    /// The sticker's size as the exporter draws it, before the tile scales it down.
    @State private var naturalSize: CGSize = .zero

    private let lime = Color(shareHex: PresetAccent.lime.hex)
    /// The copy badge's corner: 8 pt inset plus its 24 pt circle. The sticker stays below it.
    private static let badgeInset: CGFloat = 32

    var body: some View {
        // The tile takes exactly its grid column and the sticker is drawn as an overlay, so a
        // sticker wider than the column (Strip with five-digit steps) cannot widen the tile.
        Color.clear
            .frame(height: 150)
            .overlay {
                GeometryReader { proxy in
                    StickerItemView(item: item, subject: subject, totals: totals, style: style, year: year)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { naturalSize = $0 }
                        .scaleEffect(scale(fitting: proxy.size))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, Self.badgeInset)
                // Masked here and not inside the sticker: the exporter renders the same view
                // through `ImageRenderer`, which cannot draw the marker's UIKit view.
                .sentryMasked()
            }
            .background { StickerCheckerboard(isLight: style.color == .black) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(shareHex: 0xD4D4D4))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.black.opacity(0.5)))
                    .padding(8)
                    .accessibilityHidden(true)
            }
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(lime, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                LongPressGesture(minimumDuration: 0.55)
                    .onEnded { _ in onSave() }
                    .exclusively(before: TapGesture().onEnded { onCopy() })
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Save to Photos") { onSave() }
            .accessibilityAction { onCopy() }
    }

    /// Shrinks a sticker that does not fit, never enlarges one that does.
    private func scale(fitting available: CGSize) -> CGFloat {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return 1 }
        return min(1, available.width / naturalSize.width, available.height / naturalSize.height)
    }
}
