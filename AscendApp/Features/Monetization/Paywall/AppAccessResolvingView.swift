import SwiftUI

/// The surface shown while entitlement state is still `.unknown`. Routing refuses to grant or deny
/// access from an unknown answer, so this screen owns the wait - and owns the recovery when the
/// answer never arrives, so a provider outage cannot strand a subscriber on a spinner.
struct AppAccessResolvingView: View {
    @Environment(MonetizationManager.self) private var monetizationManager

    let onSignOut: () -> Void

    @State private var isRetrying = false

    var body: some View {
        Group {
            if monetizationManager.hasFailedIdentityResolution && !isRetrying {
                recoveryContent
            } else {
                loadingContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
    }

    private var loadingContent: some View {
        VStack(spacing: 16) {
            AscendLoadingIndicator()

            Text("Checking your subscription access")
                .font(.montserratMedium(size: 15))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your subscription access.")
        .accessibilityIdentifier("appAccessResolvingLoading")
    }

    private var recoveryContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.ascendAccent)
                    .accessibilityHidden(true)

                Text("Access check stalled")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Ascend could not reach your subscription. Check your connection and try again.")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appAccessResolvingStatus")
            }

            VStack(spacing: 12) {
                Button(action: retryResolution) {
                    Text("Try Again")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.ascendAccent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Checks your subscription again.")

                Button(action: onSignOut) {
                    Text("Sign Out")
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
    }

    private func retryResolution() {
        guard !isRetrying else { return }
        isRetrying = true

        Task {
            await monetizationManager.retryIdentityResolution()
            isRetrying = false
        }
    }
}

#Preview {
    AppAccessResolvingView(onSignOut: {})
        .environment(MonetizationManager())
}
