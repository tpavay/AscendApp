import SwiftUI

/// Instagram's camera mark, drawn as a shape because SF Symbols has no brand glyph.
struct InstagramGlyph: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(lineWidth: lineWidth)
            Circle()
                .stroke(lineWidth: lineWidth)
                .padding(5)
            Circle()
                .frame(width: lineWidth * 1.4, height: lineWidth * 1.4)
                .offset(x: 6, y: -6)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
