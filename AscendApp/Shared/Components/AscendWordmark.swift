import SwiftUI

/// Integrated "ASCEND" wordmark where the leading "A" is the angular brand mark.
///
/// The angular A icon plays the role of the letter A, and S/C/E/N/D follow in
/// letter-spaced Montserrat SemiBold. All sizing scales from a single `size`
/// parameter (the font size for the SCEND letters).
struct AscendWordmark: View {
    /// Font size for the letters S, C, E, N, D.
    var size: CGFloat = 14
    /// Color applied to the SCEND letters. The angular A retains its own color.
    var letterColor: Color = .white
    /// Override the default spacing between letters and between the icon and S.
    var letterSpacing: CGFloat? = nil
    /// Override the default icon frame size. Defaults to ~1.6× the font size
    /// so the angular A visually matches the cap height of the letters.
    var iconSize: CGFloat? = nil
    /// Spacing between the angular A and the S that follows. Defaults to the
    /// letter spacing minus a small optical adjustment because the A icon
    /// already has built-in trailing whitespace from its asset bounds.
    var iconTrailingSpacing: CGFloat? = nil

    private var resolvedLetterSpacing: CGFloat { letterSpacing ?? size * 0.22 }
    private var resolvedIconSize: CGFloat { iconSize ?? size * 1.6 }
    private var resolvedIconTrailingSpacing: CGFloat {
        iconTrailingSpacing ?? max(0, resolvedLetterSpacing - size * 0.15)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image("AppIconInternalAccent")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: resolvedIconSize, height: resolvedIconSize)
                .padding(.trailing, resolvedIconTrailingSpacing)
                .accessibilityHidden(true)

            HStack(spacing: resolvedLetterSpacing) {
                ForEach(Array("SCEND").map(String.init), id: \.self) { letter in
                    Text(letter)
                        .font(.montserratSemiBold(size: size))
                        .foregroundStyle(letterColor)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ascend")
    }
}

#Preview("Ascend Wordmark — sizes") {
    VStack(spacing: 28) {
        AscendWordmark(size: 11)
        AscendWordmark(size: 14)
        AscendWordmark(size: 18)
        AscendWordmark(size: 24)
        AscendWordmark(size: 36)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
