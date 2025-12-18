import Foundation
import SwiftData

/// Service for managing goals - handles CRUD and enforces single active goal
@MainActor
final class GoalService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Creates a new goal, deactivating any existing active goal
    /// - Parameters:
    ///   - metric: The metric to track (steps, floors, duration, workouts)
    ///   - target: The target value for the week
    /// - Returns: The newly created goal
    @discardableResult
    func createGoal(metric: GoalMetric, target: Int) throws -> Goal {
        // 1. Capture locked settings at creation time
        let timeZoneId = TimeZone.current.identifier
        let firstWeekday = Calendar.current.firstWeekday
        let createdWeekStart = computeWeekStart(
            for: Date(),
            timeZoneId: timeZoneId,
            firstWeekday: firstWeekday
        )

        // 2. Deactivate existing active goal (if any)
        if let existing = try getActiveGoal() {
            existing.isActive = false
        }

        // 3. Create new goal
        let goal = Goal(
            metric: metric,
            target: target,
            isActive: true,
            timeZoneId: timeZoneId,
            firstWeekday: firstWeekday,
            createdWeekStart: createdWeekStart
        )
        modelContext.insert(goal)

        // 4. Single save to avoid transient dual-active state
        try modelContext.save()

        return goal
    }

    /// Fetches the currently active goal
    func getActiveGoal() throws -> Goal? {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.isActive == true }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    /// Deactivates a goal
    func deactivateGoal(_ goal: Goal) throws {
        goal.isActive = false
        try modelContext.save()
    }

    /// Deletes a goal
    func deleteGoal(_ goal: Goal) throws {
        modelContext.delete(goal)
        try modelContext.save()
    }

    /// Computes the start of the week for a given date using specified timezone and firstWeekday
    private func computeWeekStart(for date: Date, timeZoneId: String, firstWeekday: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneId) ?? .current
        calendar.firstWeekday = firstWeekday

        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return date
        }
        return interval.start
    }
}
