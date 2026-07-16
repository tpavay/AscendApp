import SwiftUI

struct AppAccessPaywallPlaceholderView: View {
    @Environment(MonetizationManager.self) private var monetizationManager

    @State private var didPresentPaywall = false
    @State private var restoreState: RestoreState?

    private enum RestoreState: Equatable {
        case restoring
        case restored
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.ascendAccent)
                    .accessibilityHidden(true)

                Text("Access Required")
                    .font(.montserratBold(size: 34))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Ascend is built for climbers who show up. Start a subscription or restore access to keep climbing.")
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(action: presentPaywall) {
                    Text(monetizationManager.isSuperwallConfigured ? "Continue" : "Paywall Unavailable")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.black.opacity(monetizationManager.isSuperwallConfigured ? 0.9 : 0.48))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.ascendAccent.opacity(monetizationManager.isSuperwallConfigured ? 1 : 0.52))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!monetizationManager.isSuperwallConfigured)
                .accessibilityHint("Presents the Ascend subscription paywall.")

                Button(action: restorePurchases) {
                    Text(restoreButtonTitle)
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
                .disabled(restoreState == .restoring || !monetizationManager.isRevenueCatConfigured)

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
        .themedBackground()
        .onAppear {
            presentPaywall()
        }
    }

    private func presentPaywall() {
        guard monetizationManager.isSuperwallConfigured else { return }
        guard !didPresentPaywall else {
            monetizationManager.presentPaywall(
                .appAccessGate,
                params: ["source": "paywall_placeholder_retry"]
            )
            return
        }

        didPresentPaywall = true
        monetizationManager.presentPaywall(
            .appAccessGate,
            params: ["source": "app_access_gate"]
        )
    }

    private var restoreButtonTitle: String {
        guard monetizationManager.isRevenueCatConfigured else {
            return "Restore Unavailable"
        }

        switch restoreState {
        case .restoring:
            return "Restoring..."
        case .restored:
            return "Restored"
        case .failed:
            return "Restore Failed"
        case nil:
            return "Restore Purchases"
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
