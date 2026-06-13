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
                message: "You have no climbs to compare. Complete a climb to start competing.",
                action: "Browse climbs"
            )
        case .otherEmpty:
            messageCard(
                title: "HOW YOU STACK UP",
                message: "No public climbs yet. If you know this person, tell them to get on the stair stepper ASAP.",
                action: ""
            )
        case .noSharedClimbs:
            messageCard(
                title: "HOW YOU STACK UP",
                message: "No shared landmarks yet. Finish one of their climbs to see how you stack up.",
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

                    if comparison.ties > 0 {
                        Text("\(comparison.ties) tied")
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(ProfileVisualStyle.secondaryText)
                    }

                    Text("\(comparison.otherExclusiveCount) climbs they've done you haven't")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.ascendAccent)

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

                if !action.isEmpty {
                    Text(action)
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.ascendAccent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}
