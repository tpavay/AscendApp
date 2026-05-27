import SwiftUI

struct RecentWorkoutsSection: View {
    let workouts: [ProfileWorkoutSummary]
    let mode: ProfileViewMode
    let localWorkouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeaderView(
                title: "Recent Workouts",
                trailing: workouts.count >= 5 ? "View all" : nil
            )

            if workouts.isEmpty {
                ProfileCardSurfaceView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Today's climb is ready when you are.")
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(.white)

                        if mode == .own {
                            Text("Open today's climb")
                                .font(.montserratSemiBold(size: 12))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            } else {
                VStack(spacing: 7) {
                    ForEach(workouts.prefix(5)) { summary in
                        workoutRow(summary)
                    }
                }
            }
        }
    }

    private func workoutRow(_ summary: ProfileWorkoutSummary) -> some View {
        let row = ProfileCardSurfaceView {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(summary.climbTier?.color ?? (summary.isLiveClimb ? Color.accentColor : Color.white.opacity(0.18)))
                    .frame(width: 4)
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Text(ProfileDateFormatters.shortDate(summary.startedAt).uppercased())
                        .font(.montserratMedium(size: 10))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                        .tracking(0.8)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(summary.steps.formatted(.number.grouping(.automatic)))
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.white)

                    Text(ProfileDateFormatters.durationClock(summary.durationSeconds))
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                }
            }
            .frame(minHeight: 58)
            .padding(.trailing, 12)
        }

        return Group {
            if mode == .own,
               let workout = localWorkouts.first(where: { $0.id.uuidString == summary.id }) {
                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
    }
}
