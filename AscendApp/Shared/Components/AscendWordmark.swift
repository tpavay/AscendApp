import SwiftUI

/// The Ascend wordmark: the lime A with the letters beside it, drawn from the brand artwork.
///
/// Both image sets are trimmed to the lockup's visible bounds, so `height` is the height of the
/// A itself and the view's width follows from the artwork's aspect ratio. Nothing here is
/// typeset: a surface that wants a different lockup picks a ``Treatment`` rather than rebuilding
/// the letters.
struct AscendWordmark: View {
    enum Treatment: Equatable {
        /// The brand lockup, white letters in dark mode and black letters in light mode.
        case brand
        /// White letters whatever the appearance, for a surface that is always dark: a map, a photo.
        case onDark
        /// Black letters whatever the appearance, for a surface that is always light.
        case onLight
        /// One colour for the whole lockup, for a surface that owns the lockup's colour.
        case mono(Color)
        /// The A in one colour and the letters in another, for a surface whose A is not the brand lime.
        case twoColour(mark: Color, letters: Color)
    }

    /// The middle of the empty columns between the A and the S in the artwork: the A ends at 413 of
    /// 1815 and the S starts at 478.
    private static let markEdge = 446.0 / 1815.0

    /// Height of the lockup, which is the height of the A.
    var height: CGFloat = 22
    var treatment: Treatment = .brand

    var body: some View {
        lockup
            .scaledToFit()
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ascend")
    }

    @ViewBuilder
    private var lockup: some View {
        switch treatment {
        case .brand:
            Image("Wordmark").resizable()
        case .onDark:
            Image("Wordmark").resizable().environment(\.colorScheme, .dark)
        case .onLight:
            Image("Wordmark").resizable().environment(\.colorScheme, .light)
        case .mono(let color):
            Image("WordmarkMono").resizable().foregroundStyle(color)
        case .twoColour(let mark, let letters):
            Image("WordmarkMono").resizable().foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: mark, location: Self.markEdge),
                        .init(color: letters, location: Self.markEdge)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

#Preview("Ascend Wordmark") {
    VStack(spacing: 28) {
        AscendWordmark(height: 14)
        AscendWordmark(height: 22)
        AscendWordmark(height: 36)
        AscendWordmark(height: 22, treatment: .mono(.accent.opacity(0.5)))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
