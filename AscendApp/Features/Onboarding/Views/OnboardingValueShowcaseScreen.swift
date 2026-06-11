import SwiftUI

struct OnboardingValueShowcaseScreen: View {
    let activePageIndex: Int
    let pageCount: Int
    let headline: String
    let subtitle: String
    let buttonTitle: String
    let backgroundImageName: String
    let screenshotImageName: String
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            OnboardingValueShowcasePageContent(
                headline: headline,
                subtitle: subtitle,
                backgroundImageName: backgroundImageName,
                screenshotImageName: screenshotImageName
            )

            OnboardingValueShowcaseChrome(
                activePageIndex: activePageIndex,
                pageCount: pageCount,
                buttonTitle: buttonTitle,
                onContinue: onContinue
            )
        }
        .background(Color.black)
    }
}

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

struct OnboardingValueShowcaseChrome: View {
    let activePageIndex: Int
    let pageCount: Int
    let buttonTitle: String
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / 390
            let scaleY = geometry.size.height / 844

            ZStack(alignment: .top) {
                OnboardingValueShowcaseControls(
                    activePageIndex: activePageIndex,
                    pageCount: pageCount,
                    buttonTitle: buttonTitle,
                    buttonHeight: 56 * scaleY,
                    controlGap: 22 * scaleY,
                    onContinue: onContinue
                )
                .frame(width: 334 * scaleX, height: 85 * scaleY, alignment: .top)
                .position(x: geometry.size.width / 2, y: (683 + 42.5) * scaleY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct OnboardingValueShowcaseButton: View {
    let title: String
    var height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(
            OnboardingPrimaryCTAButtonStyle(
                height: height,
                cornerRadius: 12,
                fontSize: 16,
                tint: OnboardingValuePalette.lime,
                shadowOpacity: 0
            )
        )
    }
}

struct OnboardingValueShowcaseTextSection: View {
    let headline: String
    let subtitle: String
    var headlineSize: CGFloat = 30
    var subtitleSize: CGFloat = 14.5
    var stackSpacing: CGFloat = 10

    var body: some View {
        VStack(spacing: stackSpacing) {
            Text(headline)
                .font(.montserratBold(size: headlineSize))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.montserratRegular(size: subtitleSize))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct OnboardingValueShowcaseControls: View {
    let activePageIndex: Int
    let pageCount: Int
    let buttonTitle: String
    let buttonHeight: CGFloat
    var controlGap: CGFloat = 10
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingValueShowcaseCarouselDots(
                activeIndex: activePageIndex,
                totalCount: pageCount
            )

            OnboardingValueShowcaseButton(
                title: buttonTitle,
                height: buttonHeight,
                action: onContinue
            )
            .padding(.top, controlGap)
        }
    }
}

struct OnboardingValueShowcaseCarouselDots: View {
    let activeIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalCount, id: \.self) { index in
                Circle()
                    .fill(index == clampedActiveIndex ? OnboardingValuePalette.lime : Color.white.opacity(0.26))
                    .frame(width: index == clampedActiveIndex ? 7 : 5, height: index == clampedActiveIndex ? 7 : 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: clampedActiveIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(accessibilityValue)
    }

    private var clampedActiveIndex: Int {
        guard totalCount > 0 else { return 0 }
        return min(max(activeIndex, 0), totalCount - 1)
    }

    private var accessibilityValue: String {
        guard totalCount > 0 else { return "0 of 0" }
        return "\(clampedActiveIndex + 1) of \(totalCount)"
    }
}

struct OnboardingValueShowcaseScreenshot: View {
    let imageName: String
    var style: OnboardingValueScreenshotFrameStyle

    var body: some View {
        ZStack(alignment: .top) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: renderedImageWidth, height: renderedImageHeight, alignment: .top)
                .clipped()
                .offset(y: -style.topCrop)
        }
        .frame(width: style.width, height: style.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(style.borderOpacity), lineWidth: style.borderWidth)
        }
        .shadow(
            color: .black.opacity(style.shadowOpacity),
            radius: style.shadowRadius,
            x: 0,
            y: style.shadowYOffset
        )
        .allowsHitTesting(false)
    }

    private var renderedImageHeight: CGFloat {
        max(style.width * style.sourceAspectRatio, style.height + style.topCrop)
    }

    private var renderedImageWidth: CGFloat {
        renderedImageHeight / style.sourceAspectRatio
    }
}

struct OnboardingValueScreenshotFrameStyle {
    var width: CGFloat
    var height: CGFloat
    var topCrop: CGFloat
    var sourceAspectRatio: CGFloat
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var borderOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat
    var shadowOpacity: Double

    static var onboarding: OnboardingValueScreenshotFrameStyle {
        tuning
    }

    static let tuning = OnboardingValueScreenshotFrameStyle(
        width: 300,
        height: 650,
        topCrop: 30,
        sourceAspectRatio: 2622.0 / 1206.0,
        cornerRadius: 24,
        borderWidth: 1.25,
        borderOpacity: 0.32,
        shadowRadius: 18,
        shadowYOffset: 14,
        shadowOpacity: 0.34
    )
}

struct OnboardingValueShowcaseUpperBackground: View {
    let imageName: String
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.18),
                                Color.black.opacity(0.02),
                                Color.black.opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }
}

struct OnboardingValueShowcaseBottomPanel: View {
    let solidHeight: CGFloat
    let blendHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.72), location: 0.68),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: blendHeight)

            Color.black
                .frame(height: solidHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }
}

struct OnboardingValueShowcaseLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var horizontalPadding: CGFloat {
        min(max(size.width * 0.07, 24), 34)
    }

    var upperBackgroundHeight: CGFloat {
        bottomPanelSolidTop
    }

    var topBackgroundBleed: CGFloat {
        max(safeAreaInsets.top, 56)
    }

    var bottomPanelSolidTop: CGFloat {
        max(textSectionTop - 12, size.height * 0.58)
    }

    var bottomPanelSolidHeight: CGFloat {
        size.height - bottomPanelSolidTop
    }

    var bottomPanelBlendHeight: CGFloat {
        min(max(size.height * 0.085, 58), 78)
    }

    var screenshotStyle: OnboardingValueScreenshotFrameStyle {
        let base = OnboardingValueScreenshotFrameStyle.onboarding
        let width = min(size.width * 0.61, base.width)
        let scale = width / base.width

        return OnboardingValueScreenshotFrameStyle(
            width: width,
            height: base.height * scale,
            topCrop: base.topCrop * scale,
            sourceAspectRatio: base.sourceAspectRatio,
            cornerRadius: base.cornerRadius * scale,
            borderWidth: base.borderWidth,
            borderOpacity: base.borderOpacity,
            shadowRadius: base.shadowRadius,
            shadowYOffset: base.shadowYOffset,
            shadowOpacity: base.shadowOpacity
        )
    }

    var screenshotTopPadding: CGFloat {
        max(safeAreaInsets.top + 22, 68)
    }

    var screenshotHeight: CGFloat {
        screenshotStyle.height
    }

    var textSectionHeight: CGFloat {
        size.height < 740 ? 138 : 150
    }

    var textSectionTop: CGFloat {
        size.height - textSectionBottomPadding - textSectionHeight
    }

    var textSectionBottomPadding: CGFloat {
        bottomPadding + buttonHeight + 18 + 5 + textToControlsGap
    }

    var buttonHeight: CGFloat {
        size.height < 740 ? 52 : 56
    }

    var bottomPadding: CGFloat {
        max(safeAreaInsets.bottom, size.height * 34 / 844)
    }

    var textToControlsGap: CGFloat {
        size.height < 740 ? 14 : 16
    }

    var dotsToButtonGap: CGFloat {
        size.height < 740 ? 8 : 10
    }

    var heroBottomGap: CGFloat {
        size.height < 740 ? 24 : 32
    }

    var headlineSize: CGFloat {
        min(max(size.width * 0.077, 28), 30)
    }

    var subtitleSize: CGFloat {
        min(max(size.width * 0.037, 14), 15)
    }

    var textStackSpacing: CGFloat {
        10
    }
}

#Preview("Showcase Onboarding Screen") {
    OnboardingValueShowcaseScreen(
        activePageIndex: 0,
        pageCount: 4,
        headline: "Join The\nGlobal Climb",
        subtitle: "Discover climbs around the world and take them on from your own stair machine.",
        buttonTitle: "Continue",
        backgroundImageName: "OnboardingGlobalClimbsBackground",
        screenshotImageName: "OnboardingGlobalClimbsScreenshot",
        onContinue: {}
    )
}

#Preview("Screenshot Frame Tuning") {
    ZStack {
        Color.black.ignoresSafeArea()

        OnboardingValueShowcaseScreenshot(
            imageName: "OnboardingGlobalClimbsScreenshot",
            style: OnboardingValueScreenshotFrameStyle.tuning
        )
    }
}

#Preview("All Screenshot Frames") {
    ZStack {
        Color.black.ignoresSafeArea()

        HStack(spacing: 12) {
            ForEach([
                "OnboardingGlobalClimbsScreenshot",
                "OnboardingEmpireLeaderboardScreenshot",
                "OnboardingWorkoutsScreenshot",
                "OnboardingProgressScreenshot"
            ], id: \.self) { imageName in
                OnboardingValueShowcaseScreenshot(
                    imageName: imageName,
                    style: OnboardingValueScreenshotFrameStyle(
                        width: OnboardingValueScreenshotFrameStyle.tuning.width * 0.42,
                        height: OnboardingValueScreenshotFrameStyle.tuning.height * 0.42,
                        topCrop: OnboardingValueScreenshotFrameStyle.tuning.topCrop * 0.42,
                        sourceAspectRatio: OnboardingValueScreenshotFrameStyle.tuning.sourceAspectRatio,
                        cornerRadius: OnboardingValueScreenshotFrameStyle.tuning.cornerRadius * 0.42,
                        borderWidth: OnboardingValueScreenshotFrameStyle.tuning.borderWidth,
                        borderOpacity: OnboardingValueScreenshotFrameStyle.tuning.borderOpacity,
                        shadowRadius: OnboardingValueScreenshotFrameStyle.tuning.shadowRadius * 0.56,
                        shadowYOffset: OnboardingValueScreenshotFrameStyle.tuning.shadowYOffset * 0.42,
                        shadowOpacity: OnboardingValueScreenshotFrameStyle.tuning.shadowOpacity
                    )
                )
            }
        }
    }
}
