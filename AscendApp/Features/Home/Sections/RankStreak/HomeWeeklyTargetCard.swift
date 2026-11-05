import SwiftUI

/// What Home's weekly target card says about a `WeeklyTargetProgress`.
struct HomeWeeklyTargetCopy: Equatable {
    let title: String
    let detail: String
    let accessibilityLabel: String

    init(progress: WeeklyTargetProgress) {
        let target = progress.target.days
        title = "\(progress.daysClimbed) of \(target) days"

        if progress.isMet {
            detail = "Week closed. Climb again to go past it."
        } else {
            let remaining = progress.daysRemaining
            detail = remaining == 1 ? "1 more day closes your week" : "\(remaining) more days close your week"
        }

        accessibilityLabel = "Weekly target: \(progress.daysClimbed) of \(target) days climbed this week. \(detail)."
    }
}

/// The weekly ring, drawn only for a climber who set a target. It counts the days they climbed
/// this Monday week against the days they chose, and closes when they are all climbed.
struct HomeWeeklyTargetCard: View {
    let progress: WeeklyTargetProgress

    var body: some View {
        let copy = HomeWeeklyTargetCopy(progress: progress)

        HStack(spacing: 14) {
            ring

            VStack(alignment: .leading, spacing: 3) {
                Text("WEEKLY TARGET")
                    .font(.montserratSemiBold(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(Color.accent)

                Text(copy.title)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(copy.detail)
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeTileBackground())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.accessibilityLabel)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 7)

            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(
                    Color.accent,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(progress.daysClimbed.formatted())
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

#Preview("Weekly target card") {
    VStack(spacing: 12) {
        HomeWeeklyTargetCard(progress: WeeklyTargetProgress(target: WeeklyTarget(days: 3)!, daysClimbed: 2))
        HomeWeeklyTargetCard(progress: WeeklyTargetProgress(target: WeeklyTarget(days: 3)!, daysClimbed: 3))
    }
    .padding(16)
    .background(Color.black)
}
