import SwiftUI

/// Where the Connect Apple Health flow puts its controls, so the close X, the back chevron and the
/// primary button sit in the same place on every screen of it.
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

/// The glass circle in the flow's top corner: a close X where the screen ends the flow, a back
/// chevron where it steps back.
struct HealthFlowLeadingControl: View {
    enum Kind {
        case close
        case back

        var symbolName: String {
            switch self {
            case .close: "xmark"
            case .back: "chevron.backward"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .close: "Close"
            case .back: "Back"
            }
        }
    }

    let kind: Kind
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HealthFlowChrome.controlSize / 2, style: .continuous)
        Button(action: action) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: HealthFlowChrome.controlSize, height: HealthFlowChrome.controlSize)
                .contentShape(shape)
                .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.accessibilityLabel)
    }
}

extension View {
    /// Draws the flow's leading control in its one place.
    func healthFlowLeadingControl(_ kind: HealthFlowLeadingControl.Kind, action: @escaping () -> Void) -> some View {
        overlay(alignment: .topLeading) {
            HealthFlowLeadingControl(kind: kind, action: action)
                .padding(.leading, HealthFlowChrome.leadingInset)
                .padding(.top, HealthFlowChrome.topInset)
        }
    }
}

/// The bottom of every screen in the flow: an optional line above, the primary button, and a
/// reserved slot under it that holds a secondary action or stays empty.
struct HealthFlowBottomBar: View {
    let primaryTitle: String
    let primaryHeight: CGFloat
    var caption: String?
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
            }

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .tracking(2)
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
        }
    }
}
