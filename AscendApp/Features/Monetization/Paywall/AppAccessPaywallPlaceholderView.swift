import SwiftUI

struct AppAccessPaywallPlaceholderView: View {
    @Environment(MonetizationManager.self) private var monetizationManager

    @State private var hasAttemptedAutomaticPresentation = false
    @State private var presentationState = AppAccessPaywallPresentationState.presenting
    @State private var restoreState = AppAccessRestoreState.idle

    var body: some View {
        Group {
            if presentationState.showsRecoveryActions {
                recoveryContent
            } else {
                loadingContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        .onAppear {
            presentPaywallAutomaticallyIfNeeded()
        }
    }

    /// The cold-start hand-off to Superwall. It is a wait, not a wall - no lock, no access-denied
    /// headline, and no visible control the user cannot press.
    private var loadingContent: some View {
        VStack(spacing: 20) {
            Image("AppIconInternalAccent")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Preparing your climb field")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Checking your access...")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            }

            AscendLoadingIndicator()
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing your climb field. Checking your access.")
        .accessibilityIdentifier("appAccessPaywallLoading")
    }

    private var recoveryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Image("AppIconInternalAccent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                Text("Open subscription options")
                    .font(.montserratBold(size: 32))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(
                    presentationState.statusMessage
                        ?? "Choose a plan or restore your subscription to keep climbing."
                )
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("appAccessPaywallStatus")
            }

            VStack(spacing: 12) {
                Button(action: presentPaywall) {
                    Text(presentationState.primaryButtonTitle)
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.ascendAccent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Presents the Ascend subscription paywall.")

                Button(action: restorePurchases) {
                    Text(restoreState.buttonTitle(isRevenueCatConfigured: monetizationManager.isRevenueCatConfigured))
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.24), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!restoreState.isButtonEnabled(isRevenueCatConfigured: monetizationManager.isRevenueCatConfigured))

                #if DEBUG
                if monetizationManager.debugForcesAppAccessPaywall {
                    Button(action: clearDebugGateOverride) {
                        Text("Clear Debug Gate Override")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Returns the debug app to normal unentitled access.")
                }
                #endif
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func presentPaywallAutomaticallyIfNeeded() {
        guard !hasAttemptedAutomaticPresentation else { return }
        hasAttemptedAutomaticPresentation = true
        presentPaywall()
    }

    private func presentPaywall() {
        let source = hasAttemptedAutomaticPresentation && presentationState != .presenting
            ? "paywall_placeholder_retry"
            : "app_access_gate"
        presentationState.beginPresentation()
        monetizationManager.presentPaywall(
            .appAccessGate,
            params: ["source": source]
        ) { outcome in
            presentationState.handle(outcome)
        }
    }

    private func restorePurchases() {
        guard monetizationManager.isRevenueCatConfigured else {
            restoreState = .failed
            return
        }
        guard restoreState != .restoring else { return }
        restoreState = .restoring

        Task {
            do {
                try await monetizationManager.restorePurchases()
                restoreState = .restored
            } catch {
                restoreState = .failed
            }
        }
    }

    #if DEBUG
    private func clearDebugGateOverride() {
        monetizationManager.setDebugForcesAppAccessPaywall(false)
    }
    #endif
}

#Preview {
    AppAccessPaywallPlaceholderView()
        .environment(MonetizationManager())
}
