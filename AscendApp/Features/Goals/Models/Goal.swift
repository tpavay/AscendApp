import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var metric: GoalMetric
    var target: Int
    var isActive: Bool
    var createdAt: Date

    // Locked rules (captured at creation, never change)
    var timeZoneId: String
    var firstWeekday: Int
    var createdWeekStart: Date

    // Future-proofing
    var goalVersion: Int

    init(
        id: UUID = UUID(),
        metric: GoalMetric,
        target: Int,
        isActive: Bool = true,
        createdAt: Date = Date(),
        timeZoneId: String,
        firstWeekday: Int,
        createdWeekStart: Date,
        goalVersion: Int = 1
    ) {
        self.id = id
        self.metric = metric
        self.target = target
        self.isActive = isActive
        self.createdAt = createdAt
        self.timeZoneId = timeZoneId
        self.firstWeekday = firstWeekday
        self.createdWeekStart = createdWeekStart
        self.goalVersion = goalVersion
    }

    /// Returns the day name for when this goal resets (e.g., "Mon", "Sun")
    var resetDayName: String {
        WeekConfiguration.shortDayName(for: firstWeekday)
    }

    /// Returns the full reset day name (e.g., "Monday", "Sunday")
    var resetDayFullName: String {
        WeekConfiguration.fullDayName(for: firstWeekday)
    }

    /// Returns a short timezone display name (e.g., "Chicago time")
    var timeZoneDisplayName: String {
        guard let tz = TimeZone(identifier: timeZoneId) else {
            return timeZoneId
        }
        // Try to get city name from identifier (e.g., "America/Chicago" -> "Chicago")
        if let city = timeZoneId.split(separator: "/").last {
            return "\(city.replacing("_", with: " ")) time"
        }
        return tz.abbreviation() ?? timeZoneId
    }
}
