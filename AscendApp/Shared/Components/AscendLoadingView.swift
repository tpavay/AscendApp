import SwiftUI

struct AscendLoadingView: View {
    let title: String
    let message: String
    let accessibilityIdentifier: String

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 68

    init(
        title: String = "Preparing your climb field",
        message: String = "Checking your access.",
        accessibilityIdentifier: String = "ascendLoading"
    ) {
        self.title = title
        self.message = message
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        VStack(spacing: 20) {
            Image("AppIconInternalAccent")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AscendLoadingIndicator()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
