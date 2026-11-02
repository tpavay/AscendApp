import SwiftUI

/// CONNECT APPLE HEALTH: the screen that sells connecting, opened from the Climb sheet or the
/// Integrations card. The primary button goes straight to the iOS Health sheet, so connecting is
/// this tap and the sheet's own two. The close X and "Not now" both close it.
struct AppleHealthConnectView: View {
    var isWorking = false
    var errorMessage: String?
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
                    Spacer().frame(height: HealthFlowChrome.contentTopClearance)

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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(Color.ascendCaution)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                    } else {
                        Text("Next, iOS asks for access. Tap Turn On All, then Allow.")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 236)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            bottomContent: { layout in
                HealthFlowBottomBar(
                    primaryTitle: "CONNECT APPLE HEALTH",
                    primaryHeight: layout.primaryButtonHeight,
                    secondaryTitle: "Not now",
                    isDisabled: isWorking,
                    onPrimary: onConnect,
                    onSecondary: onClose
                )
            }
        )
        .healthFlowLeadingControl(.close, action: onClose)
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

            // One dashed stroke of round dots, drawn once: nothing here animates, ticks or redraws.
            Path { path in
                path.move(to: CGPoint(x: 2.5, y: 2.5))
                path.addLine(to: CGPoint(x: 68.5, y: 2.5))
            }
            .stroke(Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.01, 12]))
            .frame(width: 71, height: 5)

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
        }
        .accessibilityHidden(true)
    }
}
