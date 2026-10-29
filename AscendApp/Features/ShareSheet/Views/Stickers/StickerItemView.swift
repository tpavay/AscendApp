import SwiftUI

/// Draws a grid item through the view that owns its kind, so the tile and the exporter render the
/// same pixels for a seasonal sticker as for a standard one.
struct StickerItemView: View {
    let item: StickerItem
    let subject: ShareSheetSubject
    let totals: ShareTotalsSnapshot?
    let style: StickerStyle
    let year: Int

    var body: some View {
        switch item {
        case .standard(let kind):
            StickerView(kind: kind, subject: subject, totals: totals, style: style)
        case .seasonal(let kind):
            SeasonalStickerView(kind: kind, subject: subject, style: style, year: year)
        }
    }
}
