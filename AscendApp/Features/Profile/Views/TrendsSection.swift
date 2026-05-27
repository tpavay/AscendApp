import SwiftUI

struct TrendsSection: View {
    let trend: ProfileTrendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeaderView(title: "Trends")

            ProfileCardSurfaceView {
                VStack(alignment: .leading, spacing: 10) {
                    if !trend.hasData {
                        Text("Trends will appear after your first week of climbing.")
                            .font(.montserratMedium(size: 13))
                            .foregroundStyle(ProfileVisualStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(headline)
                                .font(.montserratBold(size: 23))
                                .foregroundStyle(changeColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text(trend.isFullMonthComparison ? "STEPS THIS MONTH" : "\(trend.daysWithData)-DAY TREND")
                                .font(.montserratBold(size: 10))
                                .foregroundStyle(ProfileVisualStyle.secondaryText)
                                .tracking(1.1)
                        }

                        miniBars
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private var headline: String {
        if let percent = trend.changePercent {
            return "\(percent >= 0 ? "+" : "")\(percent)%"
        }

        return trend.currentSteps.formatted(.number.grouping(.automatic))
    }

    private var changeColor: Color {
        (trend.changePercent ?? 0) >= 0 ? Color.accentColor : ProfileVisualStyle.danger
    }

    private var miniBars: some View {
        HStack(alignment: .bottom, spacing: 8) {
            bar(value: trend.previousSteps, maxValue: max(trend.currentSteps, trend.previousSteps), label: "LAST")
            bar(value: trend.currentSteps, maxValue: max(trend.currentSteps, trend.previousSteps), label: "NOW")
        }
        .frame(height: 70)
    }

    private func bar(value: Int, maxValue: Int, label: String) -> some View {
        let height = maxValue > 0 ? max(CGFloat(value) / CGFloat(maxValue) * 44, 6) : 6
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(label == "NOW" ? Color.accentColor : Color.white.opacity(0.22))
                .frame(width: 54, height: height)
            Text(label)
                .font(.montserratBold(size: 9))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(1)
        }
    }
}
