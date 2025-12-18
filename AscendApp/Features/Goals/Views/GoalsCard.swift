import SwiftUI
import SwiftData

struct GoalsCard: View {
    let workouts: [Workout]
    @Binding var showGoalsSheet: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel = GoalsViewModel()

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Weekly Goal")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                if viewModel.activeGoal != nil {
                    // Edit button when goal exists
                    Button(action: { showGoalsSheet = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content based on state
            if viewModel.isLoading {
                loadingState
            } else if let goal = viewModel.activeGoal, let progress = viewModel.progress {
                if progress.status == .complete {
                    completedState(goal: goal, progress: progress)
                } else {
                    inProgressState(goal: goal, progress: progress)
                }
            } else {
                emptyState
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadActiveGoal()
            viewModel.calculateProgress(from: workouts)
        }
        .onChange(of: workouts.count) { _, _ in
            viewModel.calculateProgress(from: workouts)
        }
        .onChange(of: showGoalsSheet) { oldValue, newValue in
            // Reload goal when sheet dismisses (true -> false)
            if oldValue && !newValue {
                viewModel.loadActiveGoal()
                viewModel.calculateProgress(from: workouts)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Button(action: { showGoalsSheet = true }) {
                HStack {
                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .medium))

                    Text("Set a weekly goal")
                        .font(.montserratMedium(size: 16))
                }
                .foregroundStyle(.accent)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(effectiveColorScheme == .dark ? .accent.opacity(0.15) : .accent.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        HStack {
            ProgressView()
                .tint(effectiveColorScheme == .dark ? .white : .gray)
            Text("Loading...")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .padding(.vertical, 8)
    }

    // MARK: - In Progress State

    private func inProgressState(goal: Goal, progress: GoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date range and reset info
            HStack {
                Text(progress.formattedDateRange)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                Spacer()

                Text("Resets \(goal.resetDayName)")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
            }

            // Progress text
            Text(progress.formattedProgress(metric: goal.metric))
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15))
                        .frame(height: 12)

                    // Progress fill (capped at 100%)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.accent)
                        .frame(width: geometry.size.width * min(progress.percent, 1.0), height: 12)
                }
            }
            .frame(height: 12)

            // Percentage
            Text("\(Int(progress.percent * 100))% complete")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
        }
    }

    // MARK: - Completed State

    private func completedState(goal: Goal, progress: GoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date range and reset info
            HStack {
                Text(progress.formattedDateRange)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                Spacer()

                Text("Resets \(goal.resetDayName)")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
            }

            // Celebration header
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.green)

                Text("Goal Completed!")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.green)
            }

            // Overflow count - total achieved
            Text(progress.formattedCurrent(metric: goal.metric))
                .font(.montserratBold(size: 28))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            // Full progress bar with checkmark
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.green)
                        .frame(height: 12)
                }
                .frame(height: 12)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Preview

#Preview("Empty State") {
    GoalsCard(workouts: [], showGoalsSheet: .constant(false))
        .padding(20)
}

#Preview("In Progress") {
    // This preview would need actual goal data
    GoalsCard(workouts: [], showGoalsSheet: .constant(false))
        .padding(20)
}

#Preview("Dark Mode") {
    GoalsCard(workouts: [], showGoalsSheet: .constant(false))
        .padding(20)
        .preferredColorScheme(.dark)
}
