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

    private let lime = Color(shareHex: PresetAccent.lime.hex)

    var body: some View {
        StickerItemView(item: item, subject: subject, totals: totals, style: style, year: year)
            // Masked here and not inside the sticker: the exporter renders the same view through
            // `ImageRenderer`, which cannot draw the marker's UIKit view.
            .sentryMasked()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .frame(height: 150)
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
}
