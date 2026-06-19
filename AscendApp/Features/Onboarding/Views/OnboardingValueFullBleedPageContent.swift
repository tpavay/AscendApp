import SwiftUI

struct OnboardingValueFullBleedPageContent: View {
    let headline: String
    let subtitle: String
    let heroImageName: String
    var heroFrame: OnboardingValuePage.FullBleedHeroFrame = .default

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / 390
            let scaleY = geometry.size.height / 844
            let typeScale = min(scaleX, scaleY)

            ZStack(alignment: .top) {
                Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
                    .ignoresSafeArea()

                Image(heroImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: heroFrame.width * scaleX, height: heroFrame.height * scaleY, alignment: .center)
                    .clipped()
                    .position(
                        x: (heroFrame.left + heroFrame.width / 2) * scaleX,
                        y: (heroFrame.top + heroFrame.height / 2) * scaleY
                    )
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        .black.opacity(0),
                        .black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: 281 * scaleY)
                .position(x: geometry.size.width / 2, y: (562 + 140.5) * scaleY)
                .allowsHitTesting(false)

                VStack(spacing: 11 * scaleY) {
                    Text(headline)
                        .font(.montserratBold(size: 28 * typeScale))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 340 * scaleX, height: 74 * scaleY, alignment: .center)

                    Text(subtitle)
                        .font(.montserratRegular(size: 14 * typeScale))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2 * scaleY)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 326 * scaleX, height: 44 * scaleY, alignment: .top)
                }
                .frame(width: 340 * scaleX, height: 129 * scaleY, alignment: .top)
                .position(x: geometry.size.width / 2, y: (543 + 64.5) * scaleY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
