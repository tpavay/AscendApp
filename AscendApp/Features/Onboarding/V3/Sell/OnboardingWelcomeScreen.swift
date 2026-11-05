import SwiftUI

/// 01 Welcome: the hero photo, the wordmark, the promise, and two ways in.
///
/// The photo fills the top and fades to black under the copy, zooming from 1.15 to 1 over six
/// seconds; the copy rises at 0.2, 0.4 and 0.6 s. Reduce Motion keeps the fades and drops the zoom
/// and the rise.
struct OnboardingWelcomeScreen: View {
    let coordinator: OnboardingV3Coordinator

    @OnboardingReduceMotion private var reduceMotion
    @State private var heroHasSettled = false

    var body: some View {
        // Only the photo and its gradient run under the status bar and the home indicator. A view
        // inside `ignoresSafeArea` reads zero insets, so everything is measured out here.
        GeometryReader { proxy in
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let isCompact = screenHeight < 700

            ZStack(alignment: .top) {
                backdrop(heroHeight: screenHeight * 600 / 844)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    AscendWordmark(height: 22, treatment: .onDark)
                        .padding(.top, 13)
                        .padding(.leading, 24)

                    // The words sit on the bottom of the photo; at an accessibility text size they
                    // outgrow it and scroll, while the two actions below stay put.
                    ScrollView {
                        message(isCompact: isCompact)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom, for: .alignment)
                    .defaultScrollAnchor(.top, for: .initialOffset)

                    actions
                        .padding(.horizontal, 24)
                        .padding(.top, isCompact ? 10 : 22)
                        .padding(.bottom, max(16 - proxy.safeAreaInsets.bottom, 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.6, 0.2, 1, duration: 6)) { heroHasSettled = true }
        }
        .trackOnce(screen: .onboardingWelcome)
    }

    private func backdrop(heroHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            hero(height: heroHeight)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .black.opacity(0), location: 0.18),
                    .init(color: .black.opacity(0), location: 0.40),
                    .init(color: .black.opacity(0.92), location: 0.66),
                    .init(color: .black, location: 0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func hero(height: CGFloat) -> some View {
        SellFilledImage(
            name: SellScreenAssets.welcomeHero,
            scale: heroHasSettled ? 1 : SellMotion.heroStartScale(reduceMotion: reduceMotion)
        )
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func message(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 14 : 22) {
            OnboardingHeadline(
                SellScreenCopy.Welcome.headlineLead,
                accentLines: SellScreenCopy.Welcome.headlineAccent,
                size: isCompact ? 36 : 46
            )
            .onboardingEntrance(delay: 0.2, duration: 0.6)

            Text(SellScreenCopy.Welcome.body)
                .onboardingBody()
                .fixedSize(horizontal: false, vertical: true)
                .onboardingEntrance(delay: 0.4, duration: 0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // At an accessibility text size the words grow up over the bright part of the photo, so
        // they carry their own fade to black.
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.72), location: 0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -40)
            .padding(.horizontal, -24)
            .accessibilityHidden(true)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(SellScreenCopy.Welcome.start) {
                coordinator.advance()
            }
            .buttonStyle(.onboardingPrimary)

            if let signIn = OnboardingV3Step.welcome.alternateExits.first {
                Button {
                    coordinator.go(to: signIn.destination)
                } label: {
                    Text("\(Text(SellScreenCopy.Welcome.signInPrompt))\(Text(SellScreenCopy.Welcome.signIn).foregroundStyle(Color.white))")
                }
                .buttonStyle(.onboardingQuietLink)
                .accessibilityLabel(signIn.title)
            }
        }
        .onboardingEntrance(delay: 0.6, duration: 0.6)
    }
}
