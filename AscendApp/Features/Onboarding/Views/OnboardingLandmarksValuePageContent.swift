import SwiftUI

struct OnboardingLandmarksValuePageContent: View {
    let headline: String
    let subtitle: String

    private let cards: [LandmarkCard] = [
        LandmarkCard(label: "STATUE", imageName: "OnboardingLandmarkStatueCard"),
        LandmarkCard(label: "EMPIRE", imageName: "OnboardingLandmarkEmpireCard"),
        LandmarkCard(label: "EIFFEL", imageName: "OnboardingLandmarkEiffelCard"),
        LandmarkCard(label: "BURJ", imageName: "OnboardingLandmarkBurjCard")
    ]

    var body: some View {
        GeometryReader { geometry in
            let layout = OnboardingLandmarksValueLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )

            ZStack(alignment: .top) {
                background(layout: layout)

                VStack(spacing: layout.rowSpacing) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: layout.cardGap) {
                            ForEach(0..<2, id: \.self) { column in
                                let card = cards[row * 2 + column]
                                OnboardingLandmarkCardView(card: card)
                                    .frame(width: layout.cardSize.width, height: layout.cardSize.height)
                            }
                        }
                    }
                }
                .padding(.top, layout.galleryTopPadding)
                .allowsHitTesting(false)

                textContent(layout: layout)
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(height: layout.textSectionHeight, alignment: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, layout.textSectionBottomPadding)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Climb real landmarks. Race the Statue of Liberty, Empire State Building, Eiffel Tower, and Burj Khalifa.")
    }

    private func background(layout: OnboardingLandmarksValueLayout) -> some View {
        ZStack {
            Image("OnboardingGlobalClimbsBackground")
                .resizable()
                .scaledToFill()
                .frame(width: layout.backgroundWidth, height: layout.size.height)
                .clipped()

            Color.black.opacity(0.36)

            VStack(spacing: 0) {
                Spacer()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.72), location: 0.34),
                        .init(color: .black.opacity(0.98), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: layout.copyGradientHeight)
            }

            Circle()
                .fill(OnboardingValuePalette.lime.opacity(0.1))
                .frame(width: layout.galleryGlowSize.width, height: layout.galleryGlowSize.height)
                .blur(radius: layout.galleryGlowBlur)
                .offset(y: layout.galleryGlowYOffset)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func textContent(layout: OnboardingLandmarksValueLayout) -> some View {
        VStack(spacing: 0) {
            styledHeadline
                .font(.montserratBold(size: layout.headlineSize))
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: layout.textWidth)

            Text(subtitle)
                .font(.montserratRegular(size: layout.subtitleSize))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: layout.textWidth)
                .padding(.top, layout.subtitleTopPadding)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var styledHeadline: Text {
        Text("Climb ")
            .foregroundStyle(.white)
        + Text("real\nlandmarks.")
            .foregroundStyle(OnboardingValuePalette.lime)
    }
}

private struct LandmarkCard: Identifiable {
    let label: String
    let imageName: String

    var id: String { imageName }
}

private struct OnboardingLandmarkCardView: View {
    let card: LandmarkCard

    var body: some View {
        GeometryReader { geometry in
            let cornerRadius = min(geometry.size.width * 0.145, 15)
            let labelHeight = min(geometry.size.height * 0.135, 19)

            ZStack(alignment: .bottom) {
                Image(card.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                Text(card.label)
                    .font(.montserratBold(size: min(geometry.size.width * 0.072, 7.5)))
                    .tracking(0.65)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .frame(height: labelHeight)
                    .padding(.horizontal, geometry.size.width * 0.085)
                    .background {
                        Capsule()
                            .fill(Color.black.opacity(0.62))
                    }
                    .padding(.horizontal, geometry.size.width * 0.095)
                    .padding(.bottom, geometry.size.height * 0.07)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 20, x: 0, y: 12)
        }
    }
}

private struct OnboardingLandmarksValueLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    private var sharedLayout: OnboardingValueShowcaseLayout {
        OnboardingValueShowcaseLayout(
            size: size,
            safeAreaInsets: safeAreaInsets
        )
    }

    private var scaleX: CGFloat {
        size.width / 390
    }

    private var scaleY: CGFloat {
        size.height / 844
    }

    private var typeScale: CGFloat {
        min(scaleX, scaleY)
    }

    var backgroundWidth: CGFloat {
        size.height * (676 / 844)
    }

    var copyGradientHeight: CGFloat {
        size.height - (422 * scaleY)
    }

    var galleryTopPadding: CGFloat {
        max(
            galleryMinimumTopPadding,
            sharedLayout.textSectionTop - galleryTextGap - galleryHeight
        )
    }

    var cardSize: CGSize {
        CGSize(
            width: cardHeight * (104 / 140),
            height: cardHeight
        )
    }

    var cardGap: CGFloat {
        min(max(12 * scaleX, 10), 13)
    }

    var rowSpacing: CGFloat {
        min(max(20 * scaleY, 16), 21)
    }

    var galleryGlowSize: CGSize {
        CGSize(width: 354 * scaleX, height: 310 * scaleY)
    }

    var galleryGlowBlur: CGFloat {
        48 * typeScale
    }

    var galleryGlowYOffset: CGFloat {
        -115 * scaleY
    }

    var horizontalPadding: CGFloat {
        sharedLayout.horizontalPadding
    }

    var textSectionHeight: CGFloat {
        sharedLayout.textSectionHeight
    }

    var textSectionBottomPadding: CGFloat {
        sharedLayout.textSectionBottomPadding
    }

    var textWidth: CGFloat {
        min(340, size.width - horizontalPadding * 2)
    }

    var headlineSize: CGFloat {
        sharedLayout.headlineSize
    }

    var subtitleSize: CGFloat {
        sharedLayout.subtitleSize
    }

    var subtitleTopPadding: CGFloat {
        sharedLayout.textStackSpacing
    }

    private var galleryMinimumTopPadding: CGFloat {
        safeAreaInsets.top + (size.height < 740 ? 58 : 84)
    }

    private var galleryTextGap: CGFloat {
        size.height < 740 ? 20 : 30
    }

    private var galleryHeight: CGFloat {
        (cardHeight * 2) + rowSpacing
    }

    private var cardHeight: CGFloat {
        let maximumWidth = min((size.width - horizontalPadding * 2 - cardGap * 2) / 3, 106 * scaleX)
        let maximumHeight = maximumWidth * (140 / 104)
        let availableHeight = (sharedLayout.textSectionTop - galleryMinimumTopPadding - galleryTextGap - rowSpacing) / 2
        let minimumHeight = size.height < 740 ? 104 * scaleY : 122 * typeScale

        return min(max(maximumHeight, minimumHeight), max(availableHeight, minimumHeight))
    }
}

#Preview("Landmarks Value Page") {
    if let page = OnboardingValuePages.all.first(where: { $0.id == "reason_to_come_back" }) {
        OnboardingLandmarksValuePageContent(
            headline: page.headline,
            subtitle: page.subtitle
        )
    }
}
