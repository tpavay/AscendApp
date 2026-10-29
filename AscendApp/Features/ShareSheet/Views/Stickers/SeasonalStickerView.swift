import SwiftUI

/// One transparent seasonal sticker: its content in the climber's Font, Color and Shadow, and the
/// Ascend wordmark under it, exactly like `StickerView`. No background, so it can be copied as a
/// PNG with alpha.
struct SeasonalStickerView: View {
    let kind: SeasonalStickerKind
    let subject: ShareSheetSubject
    let style: StickerStyle
    /// The year New Year's copy names, generated from the date by the caller.
    let year: Int
    let bleed: CGFloat

    init(
        kind: SeasonalStickerKind,
        subject: ShareSheetSubject,
        style: StickerStyle,
        year: Int,
        bleed: CGFloat = StickerView.defaultBleed
    ) {
        self.kind = kind
        self.subject = subject
        self.style = style
        self.year = year
        self.bleed = bleed
    }

    var body: some View {
        let ink = StickerInk(style: style)
        VStack(spacing: 7) {
            SeasonalStickerContent(kind: kind, subject: subject, ink: ink, year: year)
            AscendWordmark(size: 7, letterColor: ink.color, markColor: ink.markColor)
        }
        .stickerShadow(style)
        .padding(bleed)
        .accessibilityElement(children: .combine)
    }
}
