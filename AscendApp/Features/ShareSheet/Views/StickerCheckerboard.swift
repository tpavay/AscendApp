import SwiftUI

/// The transparency checkerboard behind a sticker tile: 12 pt squares, dark by default and light
/// when the sticker is black so it can be seen.
struct StickerCheckerboard: View {
    let isLight: Bool

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            let even = Color(shareHex: isLight ? 0xD6D6D6 : 0x1C1C1C)
            let odd = Color(shareHex: isLight ? 0xF2F2F2 : 0x151515)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(odd))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var column = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + column).isMultiple(of: 2) {
                        context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(even))
                    }
                    x += cell
                    column += 1
                }
                y += cell
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}
