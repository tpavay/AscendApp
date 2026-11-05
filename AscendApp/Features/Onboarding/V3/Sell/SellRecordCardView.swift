import SwiftUI

/// A record card: the medal on the left, the kicker, the effort's name and its number beside it.
/// Gold cards wear a laurel medal and silver cards the number 2.
struct SellRecordCardView: View {
    let card: SellRecordCard

    @ScaledMetric(relativeTo: .caption) private var kickerSize: CGFloat = 11
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 19
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 13
    @ScaledMetric(relativeTo: .headline) private var scaledMedalSize: CGFloat = 52

    /// The medal grows with the text but stops at 72 pt, so at an accessibility size the words get
    /// the room instead.
    private var medalSize: CGFloat { min(scaledMedalSize, 72) }

    private static let silver = Color(hex: "C0C0C0")
    private static let goldBorder = Color(hex: "4A3E16")
    private static let silverBorder = Color(hex: "2C3036")

    private var tint: Color { card.tier == .gold ? OnboardingV3Palette.gold : Self.silver }

    var body: some View {
        HStack(spacing: 16) {
            medal

            VStack(alignment: .leading, spacing: 3) {
                Text(card.kicker)
                    .font(.custom("Montserrat-ExtraBold", fixedSize: kickerSize))
                    .tracking(kickerSize * 0.16)
                    .foregroundStyle(tint)

                Text(card.title)
                    .font(.custom("Montserrat-ExtraBold", fixedSize: titleSize))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.detail())
                    .font(.custom("Montserrat-Medium", fixedSize: detailSize))
                    .foregroundStyle(Color(hex: "9A9A9A"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: tint.opacity(card.tier == .gold ? 0.16 : 0.10), location: 0),
                            .init(color: Color(hex: "0E0E0E"), location: 0.55)
                        ],
                        startPoint: UnitPoint(x: 0, y: 0.3),
                        endPoint: UnitPoint(x: 1, y: 0.7)
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(card.tier == .gold ? Self.goldBorder : Self.silverBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 17, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilitySummary)
    }

    private var medal: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: card.tier == .gold
                            ? [.white, OnboardingV3Palette.gold, Color(hex: "9C7A1C")]
                            : [.white, Self.silver, Color(hex: "6E7680")],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: medalSize * 0.8
                    )
                )

            switch card.tier {
            case .gold:
                // The real laurel the Progress tab crowns a record with, in ink on the gold.
                Image("BestEffortLaurel")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.black)
                    .frame(width: medalSize * 0.78)
                    .offset(y: medalSize * 0.04)
            case .silver:
                Text("\(card.tier.rank)")
                    .font(.custom("Montserrat-Black", fixedSize: medalSize * 0.385))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: medalSize, height: medalSize)
        .accessibilityHidden(true)
    }
}
