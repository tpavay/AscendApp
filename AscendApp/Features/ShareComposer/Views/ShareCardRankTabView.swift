import SwiftUI

/// The one rank treatment shared by all four finalized cards.
struct ShareCardRankTabView: View {
    let standing: ResolvedShareStanding
    let spec: ShareCardRankTabSpec
    let context: ShareCardRenderContext

    /// The tab bleeds off the card's right edge by design, so only the span from
    /// its leading inset to the card edge is ever drawn. The First Ascent lockup
    /// is sized to fit inside that, not inside `spec.width`.
    private static let badgeSize: CGFloat = 25

    var body: some View {
        HStack(spacing: 8) {
            if standing.isFirstAscent {
                Image("FirstAscentBadgeDetailed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.badgeSize, height: Self.badgeSize)

                Text("FIRST\nASCENT")
                    .font(context.font.swiftUIFont(size: 10, role: .heavy))
                    .tracking(1.15)
                    .foregroundStyle(Color(hex: "0D0D10"))
                    .lineSpacing(1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(standing.ordinalRank)
                        .font(context.font.swiftUIFont(size: 17, role: .heavy))
                    Text("OF \(standing.formattedFieldSize)")
                        .font(context.font.swiftUIFont(size: 8, role: .medium))
                        .tracking(0.9)
                }
                .foregroundStyle(Color(hex: "0D0D10"))
                .monospacedDigit()
            }
        }
        .frame(width: spec.width, height: spec.height, alignment: .leading)
        .padding(.leading, 15)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: spec.height / 2,
                bottomLeadingRadius: spec.height / 2
            )
            .fill(standing.isFirstAscent ? .white : Color(hex: "86D30A"))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            standing.isFirstAscent
                ? "First Ascent"
                : "\(standing.ordinalRank) of \(standing.formattedFieldSize)"
        )
    }
}
