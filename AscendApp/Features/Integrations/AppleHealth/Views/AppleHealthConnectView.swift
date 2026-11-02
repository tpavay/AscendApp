import SwiftUI

/// CONNECT APPLE HEALTH: the screen that sells connecting, opened from the Climb sheet or the
/// Integrations card. A close X replaces the back chevron and "Not now" closes it.
struct AppleHealthConnectView: View {
    let onConnect: () -> Void
    let onClose: () -> Void

    var body: some View {
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
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: layout.topChromeHeight + 4)

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
                    .lineLimit(1)

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

                    Spacer(minLength: 170)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            bottomContent: { layout in
                VStack(spacing: 14) {
                    Button(action: onConnect) {
                        Text("CONNECT APPLE HEALTH")
                            .tracking(2)
                    }
                    .buttonStyle(
                        OnboardingPrimaryCTAButtonStyle(
                            height: layout.primaryButtonHeight,
                            tint: .accent
                        )
                    )

                    Button("Not now", action: onClose)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(height: 36)
                }
            }
        )
        .overlay(alignment: .topLeading) {
            HealthFlowCloseButton(action: onClose)
                .padding(.leading, OnboardingChromeMetrics.backButtonLeadingPadding)
                .padding(.top, OnboardingChromeMetrics.backButtonTopPadding)
        }
        .preferredColorScheme(.dark)
        .trackOnce(screen: .appleHealthConnect)
    }

    private var linkIllustration: some View {
        HStack(spacing: 14) {
            Image("appleHealth-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 92, height: 92)
                .clipShape(.rect(cornerRadius: 24))

            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { _ in
                    Circle().fill(Color.accent).frame(width: 5, height: 5)
                }
            }

            Image(systemName: "chevron.up")
                .font(.system(size: 54, weight: .heavy))
                .foregroundStyle(Color.accent)
                .frame(width: 92, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 2)
                        )
                )
        }
        .accessibilityHidden(true)
    }
}
