import SwiftUI

/// The hard update lockout, rendered as ``AppRootRoute/updateRequired`` rather than as a sheet.
///
/// A sheet on `RootView` can be covered: Superwall presents outside that hierarchy, and a second
/// sheet at the same modifier level defers it. As a route the refusal owns the whole screen, sits
/// above authentication and the entitlement gate alike, and offers exactly one way forward (#429).
struct AppUpdateRequiredView: View {
    let onOpenAppStore: () -> Void

    private static let verdict = AppUpdatePresentation.required

    var body: some View {
        // Centred while the copy fits, scrolling once it does not. The one action on this screen is
        // the only way off it, so no accessibility text size may push it under the fold.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    refusal
                    updateAction
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .themedBackground()
        .accessibilityIdentifier("appUpdateRequiredGate")
    }

    private var refusal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.ascendAccent)
                .accessibilityHidden(true)

            Text(Self.verdict.title)
                .font(.montserratBold(size: 32))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.verdict.message)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updateAction: some View {
        Button(action: onOpenAppStore) {
            Text("Update on the App Store")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.black.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .frame(minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.ascendAccent)
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Ascend in the App Store.")
    }
}

#Preview {
    AppUpdateRequiredView(onOpenAppStore: {})
}
