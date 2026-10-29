import CoreText
import SwiftUI

/// The glyph outlines of a number in Montserrat Black, positioned as the approved board sets the
/// year: 108 point type, -0.06em tracking, left edge 16 and baseline 128.6 in the 310 point card.
/// SwiftUI has no text stroke, so the outline is the font's own glyph paths.
struct SeasonalYearOutlineShape: Shape {
    let text: String

    private static let fontSize: CGFloat = 108
    private static let tracking: CGFloat = -0.06 * 108
    private static let origin = CGPoint(x: 16, y: 128.6)

    func path(in rect: CGRect) -> Path {
        let font = CTFontCreateWithName("Montserrat-Black" as CFString, Self.fontSize, nil)
        var path = Path()
        var penX = rect.minX + Self.origin.x
        let baseline = rect.minY + Self.origin.y

        for var unit in text.utf16 {
            var glyph = CGGlyph()
            guard CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1) else { continue }
            if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
                // Font outlines are y-up; the card is y-down.
                let placement = CGAffineTransform(translationX: penX, y: baseline).scaledBy(x: 1, y: -1)
                path.addPath(Path(outline), transform: placement)
            }
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            penX += advance.width + Self.tracking
        }
        return path
    }
}
