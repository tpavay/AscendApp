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
                    subtitle: subtitle
                )
                .padding(.horizontal, layout.horizontalPadding)
                .frame(height: layout.textSectionHeight, alignment: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, layout.textSectionBottomPadding)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
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
            let layout = OnboardingValueShowcaseLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )

            ZStack(alignment: .top) {
                OnboardingValueShowcaseControls(
                    activePageIndex: activePageIndex,
                    pageCount: pageCount,
                    buttonTitle: buttonTitle,
                    buttonHeight: layout.buttonHeight,
                    onContinue: onContinue
                )
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, layout.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
                cornerRadius: 10,
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

    var body: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(.montserratBold(size: 27))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.montserratRegular(size: 14.5))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

struct OnboardingValueShowcaseControls: View {
    let activePageIndex: Int
    let pageCount: Int
    let buttonTitle: String
    let buttonHeight: CGFloat
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
            .padding(.top, 18)
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
                    .frame(width: index == clampedActiveIndex ? 5 : 4, height: index == clampedActiveIndex ? 5 : 4)
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
        size.height < 740 ? 124 : 136
    }

    var textSectionTop: CGFloat {
        size.height - textSectionBottomPadding - textSectionHeight
    }

    var textSectionBottomPadding: CGFloat {
        bottomPadding + buttonHeight + 18 + 5 + textToControlsGap
    }

    var buttonHeight: CGFloat {
        size.height < 740 ? 50 : 54
    }

    var bottomPadding: CGFloat {
        max(safeAreaInsets.bottom + 10, 28)
    }

    var textToControlsGap: CGFloat {
        size.height < 740 ? 16 : 22
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
