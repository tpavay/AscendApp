import SwiftUI

struct ComparisonBlock: View {
    let comparison: ProfileComparisonSummary

    var body: some View {
        switch comparison.state {
        case .hidden:
            EmptyView()
        case .viewerEmpty:
            messageCard(
                title: "HOW YOU STACK UP",
                message: "Climb a landmark to compare. You haven't done any of these yet.",
                action: "Browse climbs"
            )
        case .noSharedClimbs:
            messageCard(
                title: "HOW YOU STACK UP",
                message: "No shared climbs yet.",
                action: "\(comparison.otherExclusiveCount) they've done · \(comparison.viewerExclusiveCount) you've done"
            )
        case .shared:
            ProfileCardSurfaceView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HOW YOU STACK UP")
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.white)
                        .tracking(1.3)

                    Text("\(comparison.sharedClimbCount) climbs you've both done")
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.white)

                    Text("They beat you on \(comparison.otherUserWins) · You beat them on \(comparison.viewerWins)")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)

                    Text("\(comparison.otherExclusiveCount) climbs they've done you haven't")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.accentColor)

                    Text("\(comparison.viewerExclusiveCount) climbs you've done they haven't")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func messageCard(title: String, message: String, action: String) -> some View {
        ProfileCardSurfaceView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)
                    .tracking(1.3)

                Text(message)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(action)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}
