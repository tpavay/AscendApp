import SwiftUI

/// Every badge in the shelf is free-standing cut-out art, so nothing here clips or frames it:
/// a rounded-rectangle tile would slice the artwork and a stroke would draw an edge around
/// transparency. The tint survives only as the glow the art sits on.
struct ProfilePrestigeBadgeView: View {
    let token: ProfilePrestigeToken
    let imageSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            artwork

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
        .accessibilityLabel("\(token.accessibilityName), \(token.count)")
    }

    private var artwork: some View {
        ProfilePrestigeBadgeArtwork(
            asset: token.asset,
            tint: token.tint,
            size: imageSize
        )
    }
}
