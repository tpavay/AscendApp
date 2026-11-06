import SwiftUI

/// CONNECT APPLE HEALTH: the screen that sells connecting. One view in two places, because the
/// handoff drew one screen twice (06 and 06-later):
///
/// - ``Chrome/closeButton``, opened from the Climb sheet or the Integrations card. The primary
///   button goes straight to the iOS Health sheet, so connecting is this tap and the sheet's own
///   two. The close X and "Not now" both close it.
/// - ``Chrome/onboarding``, screen 06 of the first-run flow. The progress header replaces the X,
///   the quiet link says "Skip" with a line under it that connecting waits in Settings, the art
///   sits centred in the room above the words, and the one-line hint about the iOS sheet is left
///   out, because the next screen (06b) shows the sheet itself.
struct AppleHealthConnectView: View {
    enum Chrome: Equatable {
        case closeButton
        case onboarding

        /// The line under the quiet link: the way back to connecting later, said only where the climber
        /// has just chosen to skip it.
        var footnote: String? {
            switch self {
            case .closeButton: nil
            case .onboarding: "You can always connect this in Settings."
            }
        }

        var secondaryTitle: String {
            switch self {
            case .closeButton: "Not now"
            case .onboarding: "Skip"
            }
        }
    }

    var chrome: Chrome = .closeButton
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isWorking = false
    var errorMessage: String?
    let onConnect: () -> Void
    /// The close X and "Not now" for ``Chrome/closeButton``; "Skip" for ``Chrome/onboarding``.
    let onClose: () -> Void

    var body: some View {
        // Two literal call sites, one for each place the screen opens: the catalogue contract finds
        // a screen by the `trackOnce(screen: .name)` it is spelled in.
        switch chrome {
        case .closeButton: screenContent.trackOnce(screen: .healthConnectLater)
        case .onboarding: screenContent.trackOnce(screen: .onboardingHealthConnect)
        }
    }

    private var screenContent: some View {
        OnboardingScaffold(
            background: {
                ZStack {
                    Color.black
                    RadialGradient(
                        colors: [Color(red: 0.34, green: 0.05, blue: 0.1).opacity(0.5), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                    .offset(y: 40)
                }
            },
            content: { layout in
                // Scrolls only when the text size makes it: the bottom bar is laid over the content, so
                // the last line has to be able to move clear of it.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: HealthFlowChrome.contentTopClearance)

                            // Onboarding centres the art between the bar and the words; the sheet's own
                            // copy of the screen keeps it at the top, where it has always been.
                            if chrome == .onboarding {
                                Spacer(minLength: 12)
                            }

                            linkIllustration
                                .frame(maxWidth: .infinity)

                            Spacer(minLength: 12)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("YOUR WORKOUTS,")
                                    .foregroundStyle(.white)
                                Text("COUNTED FOR YOU.")
                                    .foregroundStyle(Color.accent)
                            }
                            .font(.montserratBold(size: 32))
                            .minimumScaleFactor(0.7)
                            // Each line stays one line, shrinking to fit; only at an accessibility size,
                            // where shrinking cannot save it, does a line break.
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)

                            Text("Connect Apple Health and stair stepper workouts from any device or app that saves there show up in Ascend. No typing.")
                                .font(.montserratRegular(size: 17))
                                .foregroundStyle(.white.opacity(0.62))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 12)

                            HStack(spacing: 8) {
                                ForEach(["Workouts", "Steps", "Heart rate"], id: \.self) { label in
                                    Text(label)
                                        .font(.montserratSemiBold(size: 14))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(
                                            Capsule()
                                                .fill(Color.white.opacity(0.07))
                                                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                                        )
                                }
                            }
                            .padding(.top, 16)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.montserratMedium(size: 14))
                                    .foregroundStyle(Color.ascendCaution)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 16)
                            } else if chrome == .closeButton {
                                Text("Next, iOS asks for access. Tap Turn On All, then Allow.")
                                    .font(.montserratMedium(size: 14))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 16)
                            }

                            // Room for the bar laid over the content, which is a line taller in onboarding.
                            Spacer(minLength: chrome.footnote == nil ? 190 : 206)
                        }
                        .padding(.horizontal, layout.horizontalPadding)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                }
            },
            bottomContent: { layout in
                HealthFlowBottomBar(
                    primaryTitle: "CONNECT APPLE HEALTH",
                    primaryHeight: layout.primaryButtonHeight,
                    footnote: chrome.footnote,
                    secondaryTitle: chrome.secondaryTitle,
                    isDisabled: isWorking,
                    onPrimary: onConnect,
                    onSecondary: onClose
                )
                // At an accessibility size the text scrolls under the bar, so it needs a floor to be cut
                // against; at every other size nothing reaches it and the glow stays unbroken.
                .background(dynamicTypeSize.isAccessibilitySize ? Color.black : Color.clear)
            }
        )
        .overlay(alignment: .top) {
            if chrome == .onboarding {
                OnboardingProgressHeader(step: .healthConnect)
                    .padding(.top, 9)
            }
        }
        .healthFlowCloseControl(action: onClose, isShown: chrome == .closeButton)
        .preferredColorScheme(.dark)
    }

    private var linkIllustration: some View {
        HStack(spacing: 14) {
            Image("appleHealth-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 92, height: 92)
                .clipShape(.rect(cornerRadius: 24))
                .onboardingEntrance(style: .pop, delay: 0.1)

            HealthLinkDots()

            Image("AppIconInternalAccent")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .padding(22)
                .frame(width: 92, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 2)
                        )
                )
                .onboardingEntrance(style: .pop, delay: 0.25)
        }
        .accessibilityHidden(true)
    }
}

/// The dotted line between the two tiles: round dots that flow from Health toward Ascend, one
/// 12 pt step every 0.4 s, which is the design's 24 pt in 0.8 s. Reduce Motion holds it still.
private struct HealthLinkDots: View {
    /// One dot and its gap, so a full step lands the pattern back where it began.
    private static let period: CGFloat = 12.01

    @OnboardingReduceMotion private var reduceMotion
    @State private var phase: CGFloat = HealthLinkDots.period

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 2.5, y: 2.5))
            path.addLine(to: CGPoint(x: 68.5, y: 2.5))
        }
        .stroke(
            Color.accent,
            style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.01, 12], dashPhase: phase)
        )
        .frame(width: 71, height: 5)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: false)) {
                phase = 0
            }
        }
    }
}
