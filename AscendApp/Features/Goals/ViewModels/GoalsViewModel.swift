import Foundation
import SwiftData

@MainActor
@Observable
class GoalsViewModel {
    private var goalService: GoalService?

    var activeGoal: Goal?
    var progress: GoalProgress?
    var lastWeekProgress: GoalProgress?
    var isLoading = false
    var errorMessage: String?

    /// Configure the view model with a model context
    func configure(modelContext: ModelContext) {
        self.goalService = GoalService(modelContext: modelContext)
    }

    /// Load the active goal
    func loadActiveGoal() {
        guard let goalService else { return }

        isLoading = true
        errorMessage = nil

        do {
            activeGoal = try goalService.getActiveGoal()
        } catch {
            errorMessage = "Failed to load goal: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Calculate progress for the active goal from workouts
    func calculateProgress(from workouts: [Workout]) {
        guard let goal = activeGoal else {
            progress = nil
            lastWeekProgress = nil
            return
        }

        progress = GoalProgressService.calculateProgress(for: goal, from: workouts)
        lastWeekProgress = GoalProgressService.calculateLastWeekProgress(for: goal, from: workouts)
    }

    /// Create a new goal (replaces any existing active goal)
    func createGoal(metric: GoalMetric, target: Int) {
        guard let goalService else { return }

        isLoading = true
        errorMessage = nil

        do {
            activeGoal = try goalService.createGoal(metric: metric, target: target)
        } catch {
            errorMessage = "Failed to create goal: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Deactivate the current goal
    func deactivateGoal() {
        guard let goalService, let goal = activeGoal else { return }

        isLoading = true
        errorMessage = nil

        do {
            try goalService.deactivateGoal(goal)
            activeGoal = nil
            progress = nil
            lastWeekProgress = nil
        } catch {
            errorMessage = "Failed to deactivate goal: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Delete the current goal
    func deleteGoal() {
        guard let goalService, let goal = activeGoal else { return }

        isLoading = true
        errorMessage = nil

        do {
            try goalService.deleteGoal(goal)
            activeGoal = nil
            progress = nil
            lastWeekProgress = nil
        } catch {
            errorMessage = "Failed to delete goal: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Display Helpers

    /// Returns the reset day info for display (e.g., "Mon", "Sun")
    var resetDayName: String {
        if let goal = activeGoal {
            return goal.resetDayName
        }
        // If no goal, use current locale's first weekday
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let index = (Calendar.current.firstWeekday - 1) % 7
        return dayNames[index]
    }

    /// Returns the full reset day info (e.g., "Monday", "Sunday")
    var resetDayFullName: String {
        if let goal = activeGoal {
            return goal.resetDayFullName
        }
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let index = (Calendar.current.firstWeekday - 1) % 7
        return dayNames[index]
    }

    /// Returns the timezone display name for the current context
    var timeZoneDisplayName: String {
        if let goal = activeGoal {
            return goal.timeZoneDisplayName
        }
        // If no goal, use current timezone
        let tz = TimeZone.current
        if let city = tz.identifier.split(separator: "/").last {
            return "\(city.replacing("_", with: " ")) time"
        }
        return tz.abbreviation() ?? tz.identifier
    }
}
