import SwiftUI

struct WorkoutCompleteView: View {
    let routineName: String
    let duration: TimeInterval
    let intervalCount: Int
    var primaryActionTitle = "Log Workout"
    var onLogWorkout: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Metrics.contentSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: Metrics.checkmarkSize, weight: .light))
                    .foregroundStyle(.accent)
                    .padding(.top, Metrics.checkmarkTopPadding)

                VStack(spacing: Metrics.titleSpacing) {
                    Text("Workout Complete!")
                        .font(.montserratBold(size: Metrics.titleFontSize))
                        .foregroundStyle(.white)

                    Text(routineName)
                        .font(.montserratMedium(size: Metrics.subtitleFontSize))
                        .foregroundStyle(.white.opacity(Metrics.subtitleOpacity))
                }

                HStack(spacing: Metrics.statSpacing) {
                    statBlock(value: formatDuration(duration), label: "Duration")
                    statBlock(value: "\(intervalCount)", label: "Intervals")
                }
                .padding(.horizontal, Metrics.statsHorizontalPadding)
                .padding(.vertical, Metrics.statsVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.statsCornerRadius)
                        .fill(.white.opacity(Metrics.statsBackgroundOpacity))
                )

                Spacer()

                VStack(spacing: Metrics.actionSpacing) {
                    Button(action: onLogWorkout) {
                        Text(primaryActionTitle)
                            .font(.montserratSemiBold(size: Metrics.primaryActionFontSize))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Metrics.primaryActionVerticalPadding)
                            .background(
                                RoundedRectangle(cornerRadius: Metrics.primaryActionCornerRadius)
                                    .fill(.accent)
                            )
                    }

                    Button(action: onDiscard) {
                        Text("Don't Save")
                            .font(.montserratMedium(size: Metrics.secondaryActionFontSize))
                            .foregroundStyle(.white.opacity(Metrics.secondaryActionOpacity))
                    }
                }
                .padding(.horizontal, Metrics.actionsHorizontalPadding)
                .padding(.bottom, Metrics.actionsBottomPadding)
            }
            .background(Color.black)
        }
        .interactiveDismissDisabled()
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: Metrics.statLabelSpacing) {
            Text(value)
                .font(.montserratBold(size: Metrics.statValueFontSize))
                .foregroundStyle(.white)

            Text(label)
                .font(.montserratRegular(size: Metrics.statLabelFontSize))
                .foregroundStyle(.white.opacity(Metrics.statLabelOpacity))
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }
}

private enum Metrics {
    static let contentSpacing: CGFloat = 32
    static let checkmarkSize: CGFloat = 80
    static let checkmarkTopPadding: CGFloat = 20
    static let titleSpacing: CGFloat = 8
    static let titleFontSize: CGFloat = 28
    static let subtitleFontSize: CGFloat = 18
    static let subtitleOpacity = 0.7

    static let statSpacing: CGFloat = 32
    static let statLabelSpacing: CGFloat = 4
    static let statValueFontSize: CGFloat = 28
    static let statLabelFontSize: CGFloat = 14
    static let statLabelOpacity = 0.6
    static let statsHorizontalPadding: CGFloat = 32
    static let statsVerticalPadding: CGFloat = 24
    static let statsCornerRadius: CGFloat = 16
    static let statsBackgroundOpacity = 0.05

    static let actionSpacing: CGFloat = 12
    static let primaryActionFontSize: CGFloat = 16
    static let primaryActionVerticalPadding: CGFloat = 16
    static let primaryActionCornerRadius: CGFloat = 12
    static let secondaryActionFontSize: CGFloat = 14
    static let secondaryActionOpacity = 0.6
    static let actionsHorizontalPadding: CGFloat = 20
    static let actionsBottomPadding: CGFloat = 20
}

#Preview {
    WorkoutCompleteView(
        routineName: "Pyramid Climb",
        duration: 1_152,
        intervalCount: 9,
        onLogWorkout: {},
        onDiscard: {}
    )
}
