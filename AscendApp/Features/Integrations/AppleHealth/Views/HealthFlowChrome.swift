import SwiftUI

/// Where the Connect Apple Health flow puts its controls, so the close X and the primary button sit in
/// the same place on every screen of it.
///
/// The top inset is measured from the safe area, where an app header's own controls sit, not from
/// the screen's edge the way onboarding's progress-bar screens do.
enum HealthFlowChrome {
    static let controlSize: CGFloat = OnboardingChromeMetrics.backButtonSize
    static let leadingInset: CGFloat = 16
    static let topInset: CGFloat = 6
    /// Room kept under every screen's primary button for a secondary action, used or not, so the
    /// primary button never moves between screens.
    static let secondarySlotHeight: CGFloat = 36
    static let primarySpacing: CGFloat = 14
    /// Height from the safe area's top to the first line of content, clear of the control.
    static let contentTopClearance: CGFloat = topInset + controlSize + 24
}

/// The glass close X in the flow's top corner.
struct HealthFlowCloseControl: View {
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HealthFlowChrome.controlSize / 2, style: .continuous)
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: HealthFlowChrome.controlSize, height: HealthFlowChrome.controlSize)
                .contentShape(shape)
                .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

extension View {
    /// Draws the flow's close X in its one place. Onboarding's copy of the Connect screen draws
    /// its progress header there instead and passes `isShown: false`.
    func healthFlowCloseControl(action: @escaping () -> Void, isShown: Bool = true) -> some View {
        overlay(alignment: .topLeading) {
            if isShown {
                HealthFlowCloseControl(action: action)
                    .padding(.leading, HealthFlowChrome.leadingInset)
                    .padding(.top, HealthFlowChrome.topInset)
            }
        }
    }
}

/// The bottom of every screen in the flow: an optional line above, the primary button, and a
/// reserved slot under it that holds a secondary action or stays empty.
struct HealthFlowBottomBar: View {
    let primaryTitle: String
    let primaryHeight: CGFloat
    var caption: String?
    /// A line under the secondary action, for the screen that says where the skipped step lives.
    var footnote: String?
    var secondaryTitle: String?
    var isDisabled = false
    let onPrimary: () -> Void
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(spacing: HealthFlowChrome.primarySpacing) {
            if let caption {
                Text(caption)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .tracking(2)
                    // One line that shrinks to fit, so a long title at a large text size is never
                    // cut to an ellipsis.
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(OnboardingPrimaryCTAButtonStyle(height: primaryHeight, tint: .accent))
            .disabled(isDisabled)

            Group {
                if let secondaryTitle {
                    Button(secondaryTitle, action: onSecondary)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Color.clear
                }
            }
            .frame(height: HealthFlowChrome.secondarySlotHeight)

            if let footnote {
                Text(footnote)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
