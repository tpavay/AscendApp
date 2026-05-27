import SwiftUI

struct ActivityCalendarSection: View {
    let workouts: [ProfileWorkoutSummary]
    let currentStreakWeeks: Int
    let bestStreakWeeks: Int
    let mode: ProfileViewMode

    @State private var selectedDate = Date()

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeaderView(title: "Activity")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    calendarGrid
                        .frame(minWidth: 0, maxWidth: .infinity)

                    StreakPanel(
                        currentStreakWeeks: currentStreakWeeks,
                        bestStreakWeeks: bestStreakWeeks
                    )
                    .frame(width: 62)
                }

                VStack(alignment: .leading, spacing: 12) {
                    calendarGrid

                    StreakPanel(
                        currentStreakWeeks: currentStreakWeeks,
                        bestStreakWeeks: bestStreakWeeks
                    )
                }
            }

            if mode == .own, workouts.isEmpty {
                Text("Your climbing days will light up here.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var calendarGrid: some View {
        ProfileCardSurfaceView {
            VStack(spacing: 10) {
                monthControl

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                    spacing: 7
                ) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.montserratSemiBold(size: 9))
                            .foregroundStyle(ProfileVisualStyle.secondaryText)
                            .frame(height: 14)
                    }

                    ForEach(calendarDays) { day in
                        Text("\(calendar.component(.day, from: day.date))")
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(day.isCurrentMonth ? .white : ProfileVisualStyle.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(dayFill(day))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
    }

    private var monthControl: some View {
        HStack(spacing: 8) {
            monthButton(
                title: "Previous month",
                systemName: "chevron.left",
                isEnabled: true
            ) {
                selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            }

            Text(monthYearFormatter.string(from: selectedDate).uppercased())
                .font(.montserratBold(size: 12))
                .foregroundStyle(Color.accentColor)
                .tracking(1.2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            monthButton(
                title: "Next month",
                systemName: "chevron.right",
                isEnabled: canGoToNextMonth
            ) {
                selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            }
        }
    }

    private func monthButton(
        title: String,
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemName) {
            guard isEnabled else { return }
            action()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(isEnabled ? Color.accentColor : ProfileVisualStyle.tertiaryText)
        .frame(width: 28, height: 26)
        .contentShape(Rectangle())
        .disabled(!isEnabled)
    }

    private var canGoToNextMonth: Bool {
        let next = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        return calendar.compare(next, to: Date(), toGranularity: .month) != .orderedDescending
    }

    private var calendarDays: [ProfileCalendarDayModel] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let daysFromMonday = (firstWeekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: monthInterval.start) ?? monthInterval.start
        let lastWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        let daysToSunday = (8 - lastWeekday) % 7
        let gridEnd = calendar.date(byAdding: .day, value: daysToSunday, to: lastDayOfMonth) ?? lastDayOfMonth
        var days: [ProfileCalendarDayModel] = []
        var current = gridStart

        while current <= gridEnd {
            let dayStart = calendar.startOfDay(for: current)
            let steps = stepsByDay[dayStart] ?? 0
            days.append(
                ProfileCalendarDayModel(
                    date: dayStart,
                    steps: steps,
                    isCurrentMonth: calendar.isDate(dayStart, equalTo: selectedDate, toGranularity: .month)
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return days
    }

    private var stepsByDay: [Date: Int] {
        workouts.reduce(into: [Date: Int]()) { result, workout in
            let key = calendar.startOfDay(for: workout.startedAt)
            result[key, default: 0] += workout.steps
        }
    }

    private var maxSteps: Int {
        calendarDays.map(\.steps).max() ?? 0
    }

    private func dayFill(_ day: ProfileCalendarDayModel) -> Color {
        guard day.isCurrentMonth else { return Color.white.opacity(0.035) }
        guard day.steps > 0, maxSteps > 0 else { return Color.white.opacity(0.075) }
        let progress = min(Double(day.steps) / Double(maxSteps), 1)
        return Color(
            red: 0.20 + 0.42 * progress,
            green: 0.34 + 0.46 * progress,
            blue: 0.03 + 0.03 * progress
        )
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }
}

private struct ProfileCalendarDayModel: Identifiable {
    let date: Date
    let steps: Int
    let isCurrentMonth: Bool

    var id: Date { date }
}

private struct StreakPanel: View {
    let currentStreakWeeks: Int
    let bestStreakWeeks: Int

    var body: some View {
        VStack(spacing: 6) {
            Text("WEEK STREAK")
                .font(.montserratBold(size: 7))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            streak(label: "CURRENT", value: currentStreakWeeks, icon: "flame.fill", tint: .orange)

            Divider()
                .frame(maxWidth: 38)
                .overlay(Color.white.opacity(0.14))

            streak(label: "BEST", value: bestStreakWeeks, icon: "trophy.fill", tint: ProfileVisualStyle.gold)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 1)
    }

    private func streak(label: String, value: Int, icon: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)

            Text(value.formatted(.number.grouping(.automatic)))
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)

            Text(label)
                .font(.montserratBold(size: 7))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}
