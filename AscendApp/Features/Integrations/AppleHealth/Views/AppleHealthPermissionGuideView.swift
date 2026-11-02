import SwiftUI

/// TWO TAPS AND YOU'RE SET: what the iOS Health sheet looks like and which two taps clear it,
/// shown before the sheet so the climber turns everything on instead of dismissing it.
///
/// The toggles drawn here are the four reads Ascend requests, and nothing else
/// (`HealthKitAuthorizationClient.readTypes`).
struct AppleHealthPermissionGuideView: View {
    let isWorking: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onConfirm: () -> Void

    private let permissionRows = ["Heart Rate", "Steps", "Workouts", "Active Energy"]

    var body: some View {
        OnboardingScaffold(
            backAction: onBack,
            background: { Color.black },
            content: { layout in
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: layout.topChromeHeight + 2)

                    mockSheet
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("TWO TAPS AND")
                            .foregroundStyle(.white)
                        Text("YOU'RE SET.")
                            .foregroundStyle(Color.accent)
                    }
                    .font(.montserratBold(size: 32))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        stepLine(number: 1, leading: "Tap", highlight: "Turn On All", trailing: nil)
                        stepLine(number: 2, leading: "Tap", highlight: "Allow", trailing: "in the top right")
                    }
                    .padding(.top, 12)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(Color.ascendCaution)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 110)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            bottomContent: { layout in
                Button(action: onConfirm) {
                    Text("GOT IT")
                        .tracking(2)
                }
                .buttonStyle(
                    OnboardingPrimaryCTAButtonStyle(height: layout.primaryButtonHeight, tint: .accent)
                )
                .disabled(isWorking)
            }
        )
        .preferredColorScheme(.dark)
        .trackOnce(screen: .appleHealthPermissionGuide)
    }

    private func stepLine(number: Int, leading: String, highlight: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            numberChip(number)
            Text(leading).foregroundStyle(.white)
            Text(highlight).foregroundStyle(Color.accent)
            if let trailing {
                Text(trailing).foregroundStyle(.white)
            }
        }
        .font(.montserratBold(size: 20))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func numberChip(_ number: Int) -> some View {
        Text("\(number)")
            .font(.montserratBold(size: 15))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.accent))
    }

    /// A drawn stand-in for the iOS sheet: the two controls to tap are ringed and numbered.
    private var mockSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Don't Allow")
                    .foregroundStyle(Color.blue)
                Spacer()
                Text("Health Access")
                    .foregroundStyle(.white)
                Spacer()
                Text("Allow")
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accent, lineWidth: 2)
                    )
                    .overlay(alignment: .topTrailing) {
                        numberChip(2).offset(x: 8, y: -26)
                    }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().overlay(.white.opacity(0.12))

            Image(systemName: "chevron.up")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
                .padding(.top, 12)

            Text("\"Ascend\" would like to access your Health data.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            Text("Turn On All")
                .font(.system(size: 14))
                .foregroundStyle(Color.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accent, lineWidth: 2)
                )
                .overlay(alignment: .topLeading) {
                    numberChip(1).offset(x: -4, y: -12)
                }
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                ForEach(permissionRows, id: \.self) { row in
                    HStack {
                        Text(row)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                        Spacer()
                        Capsule()
                            .fill(Color.green)
                            .frame(width: 34, height: 20)
                            .overlay(alignment: .trailing) {
                                Circle().fill(.white).frame(width: 16, height: 16).padding(.trailing, 2)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    if row != permissionRows.last {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 2)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Health Access sheet. Tap Turn On All, then tap Allow in the top right.")
    }
}
