import SwiftUI

struct AppAccessPaywallPlaceholderView: View {
    @Environment(MonetizationManager.self) private var monetizationManager

    let onRestore: () -> Void
    @State private var didPresentPaywall = false

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

                Button(action: onRestore) {
                    Text("Restore Purchases")
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
                .onboardingPaywall,
                params: ["source": "paywall_placeholder_retry"]
            )
            return
        }

        didPresentPaywall = true
        monetizationManager.presentPaywall(
            .onboardingPaywall,
            params: ["source": "post_auth_onboarding"]
        )
    }
}

#Preview {
    AppAccessPaywallPlaceholderView(onRestore: {})
        .environment(MonetizationManager())
}
