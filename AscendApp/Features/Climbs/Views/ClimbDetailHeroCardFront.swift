import SwiftUI

struct ClimbDetailHeroCardFront<Artwork: View>: View {
    let climb: Climb
    let subtitle: String
    let stripOrderText: String?
    let artwork: Artwork

    init(
        climb: Climb,
        subtitle: String,
        stripOrderText: String?,
        @ViewBuilder artwork: () -> Artwork
    ) {
        self.climb = climb
        self.subtitle = subtitle
        self.stripOrderText = stripOrderText
        self.artwork = artwork()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork

            LinearGradient(
                colors: [
                    .black.opacity(0.03),
                    .black.opacity(0.1),
                    .black.opacity(0.22),
                    .black.opacity(0.52)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let stripOrderText {
                HStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 28,
                            bottomLeading: 28,
                            bottomTrailing: 0,
                            topTrailing: 0
                        ),
                        style: .continuous
                    )
                    .fill(climb.tier.detailStripStyle)
                    .frame(width: 48)
                    .overlay {
                        Text(stripOrderText)
                            .font(.montserratBold(size: 12))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(-90))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                    }

                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.18),
                        .black.opacity(0.68),
                        .black.opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 132)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(climb.name)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 4)
            .padding(.leading, stripOrderText == nil ? 20 : 64)
            .padding(.trailing, 16)
            .padding(.bottom, 70)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
