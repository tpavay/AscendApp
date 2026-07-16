import SwiftUI

struct OnboardingValueShowcasePageContent: View {
    let headline: String
    let subtitle: String
    let backgroundImageName: String
    let screenshotImageName: String

    var body: some View {
        GeometryReader { geometry in
            let layout = OnboardingValueShowcaseLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )

            ZStack(alignment: .top) {
                OnboardingValueShowcaseUpperBackground(
                    imageName: backgroundImageName,
                    height: layout.upperBackgroundHeight + layout.topBackgroundBleed
                )
                .offset(y: -layout.topBackgroundBleed)

                OnboardingValueShowcaseBottomPanel(
                    solidHeight: layout.bottomPanelSolidHeight,
                    blendHeight: layout.bottomPanelBlendHeight
                )

                OnboardingValueShowcaseScreenshot(
                    imageName: screenshotImageName,
                    style: layout.screenshotStyle
                )
                .padding(.top, layout.screenshotTopPadding)

                OnboardingValueShowcaseTextSection(
                    headline: headline,
                    subtitle: subtitle,
                    headlineSize: layout.headlineSize,
                    subtitleSize: layout.subtitleSize,
                    stackSpacing: layout.textStackSpacing
                )
                .padding(.horizontal, layout.horizontalPadding)
                .frame(height: layout.textSectionHeight, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, layout.textSectionBottomPadding)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
        }
    }
}
