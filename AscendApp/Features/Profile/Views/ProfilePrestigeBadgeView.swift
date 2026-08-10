import SwiftUI

struct ProfilePrestigeBadgeView: View {
    let token: ProfilePrestigeToken
    let imageSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if token.usesFreeStandingArt {
                    Image(token.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize, height: imageSize)
                } else {
                    Image(token.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(token.tint.opacity(0.42), lineWidth: 1)
                        )
                }
            }
            .shadow(color: token.tint.opacity(0.26), radius: 6, y: 2)

            Text(token.count.formatted(.number.grouping(.automatic)))
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            Text(token.label.uppercased())
                .font(.montserratSemiBold(size: 9))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 88)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.label), \(token.count)")
    }
}
