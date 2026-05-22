import SwiftUI

struct OnboardingValueScreen<Background: View, Hero: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let activePageIndex: Int
    let pageCount: Int
    let headline: String
    let subtitle: String
    let buttonTitle: String
    var parallaxOffset: CGFloat = 0
    let onContinue: () -> Void

    private let background: () -> Background
    private let hero: () -> Hero

    init(
        activePageIndex: Int,
        pageCount: Int,
        headline: String,
        subtitle: String,
        buttonTitle: String = "Continue",
        parallaxOffset: CGFloat = 0,
        onContinue: @escaping () -> Void,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder hero: @escaping () -> Hero
    ) {
        self.activePageIndex = activePageIndex
        self.pageCount = pageCount
        self.headline = headline
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.parallaxOffset = parallaxOffset
        self.onContinue = onContinue
        self.background = background
        self.hero = hero
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = OnboardingValueScreenLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )

            ZStack {
                background()
                    .frame(
                        width: geometry.size.width + layout.backgroundBleed,
                        height: geometry.size.height + layout.backgroundVerticalBleed
                    )
                    .offset(
                        x: reduceMotion ? 0 : parallaxOffset,
                        y: layout.backgroundYOffset
                    )
                    .clipped()
                    .ignoresSafeArea()

                backgroundWash

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: layout.heroTopPadding)

                    hero()
                        .frame(width: layout.heroWidth)
                        .offset(y: layout.heroYOffset)
                        .allowsHitTesting(false)

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                bottomReadabilityScrim

                VStack(spacing: 0) {
                    OnboardingValueProgressIndicator(
                        activeIndex: activePageIndex,
                        totalCount: pageCount
                    )
                    .padding(.top, layout.progressTopPadding)

                    Spacer(minLength: 0)
                }

                bottomContent(layout: layout)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
        }
    }

    private var backgroundWash: some View {
        ZStack {
            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.44)
                ],
                center: .center,
                startRadius: 220,
                endRadius: 620
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    .clear,
                    Color.black.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private var bottomReadabilityScrim: some View {
        VStack(spacing: 0) {
            Spacer()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.52), location: 0.34),
                    .init(color: Color.black.opacity(0.94), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 330)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    private func bottomContent(layout: OnboardingValueScreenLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(headline)
                .font(.montserratBold(size: layout.headlineSize))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(1)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(.montserratMedium(size: layout.subtitleSize))
                .foregroundStyle(Color(red: 168 / 255, green: 168 / 255, blue: 168 / 255))
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)

            Button(action: onContinue) {
                Text(buttonTitle)
            }
            .buttonStyle(
                OnboardingPrimaryCTAButtonStyle(
                    height: layout.buttonHeight,
                    tint: .accent,
                    shadowOpacity: 0.26
                )
            )
            .padding(.top, layout.buttonTopPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .bottom)
    }
}

private struct OnboardingValueScreenLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var backgroundBleed: CGFloat {
        90
    }

    var backgroundVerticalBleed: CGFloat {
        100
    }

    var backgroundYOffset: CGFloat {
        -30
    }

    var horizontalPadding: CGFloat {
        min(max(size.width * 0.075, 26), 34)
    }

    var progressTopPadding: CGFloat {
        safeAreaInsets.top + 58
    }

    var heroTopPadding: CGFloat {
        max(safeAreaInsets.top + 8, size.height * 0.035)
    }

    var heroYOffset: CGFloat {
        -28
    }

    var heroWidth: CGFloat {
        min(size.width * 0.8, 350)
    }

    var headlineSize: CGFloat {
        size.width < 370 ? 34 : 37
    }

    var subtitleSize: CGFloat {
        size.width < 370 ? 15.5 : 16.5
    }

    var buttonHeight: CGFloat {
        size.height < 700 ? 56 : 58
    }

    var buttonTopPadding: CGFloat {
        size.height < 700 ? 24 : 30
    }

    var bottomPadding: CGFloat {
        safeAreaInsets.bottom + 18
    }
}
