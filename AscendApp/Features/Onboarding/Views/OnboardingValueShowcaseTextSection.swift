import SwiftUI

struct OnboardingValueShowcaseTextSection: View {
    let headline: String
    let subtitle: String
    var headlineSize: CGFloat = 30
    var subtitleSize: CGFloat = 14.5
    var stackSpacing: CGFloat = 10

    var body: some View {
        VStack(spacing: stackSpacing) {
            Text(headline)
                .font(.montserratBold(size: headlineSize))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.montserratRegular(size: subtitleSize))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
