import Foundation

enum WorkoutInputValidation {
    static let nameMaxLength = 120
    static let notesMaxLength = 5_000
    static let minimumHeartRate = 25
    static let maximumHeartRate = 230

    static func isValidOptionalSteps(_ value: String) -> Bool {
        guard value.isEmpty == false else { return true }
        guard let intValue = Int(value) else { return false }
        return intValue >= 0
    }

    /// Whether the edited totals are inside the envelope the climb's origin is held to: the 220
    /// steps/min sensor gate for a live climb, and for one the climber typed in the refusal line
    /// in `ClimbPacePolicy` - a climb between that gate and the leaderboard ceiling is saved, not
    /// refused.
    static func isValidWorkoutTotals(
        origin: ClimbOrigin = .live,
        stepsValue: String,
        durationHours: Int,
        durationMinutes: Int,
        durationSeconds: Int
    ) -> Bool {
        let steps = Int(stepsValue) ?? 0
        let totalDuration = TimeInterval(durationHours * 3_600 + durationMinutes * 60 + durationSeconds)

        guard WorkoutPlausibilityPolicy.hasPlausibleTotals(
            origin: origin,
            steps: steps,
            duration: totalDuration
        ) else {
            return false
        }
        guard origin != .live else { return true }
        return steps <= ClimbPacePolicy.maximumSteps && totalDuration <= ClimbPacePolicy.maximumDuration
    }

    static func isValidWorkoutName(_ value: String) -> Bool {
        value.isEmpty || value.count <= nameMaxLength
    }

    static func isValidNotes(_ value: String) -> Bool {
        value.count <= notesMaxLength
    }

    static func isValidOptionalHeartRate(_ value: String) -> Bool {
        guard value.isEmpty == false else { return true }
        guard let intValue = Int(value) else { return false }
        return intValue >= minimumHeartRate && intValue <= maximumHeartRate
    }

    static func isValidOptionalCalories(_ value: String) -> Bool {
        guard value.isEmpty == false else { return true }
        guard let intValue = Int(value) else { return false }
        return intValue >= 0
    }

    static func filterNumericInput(_ input: String) -> String {
        input.filter(\.isNumber)
    }

    static func normalizeHeartRateOnSubmit(_ value: String) -> String {
        let digits = filterNumericInput(value)
        guard digits.isEmpty == false else { return "" }
        guard let intValue = Int(digits) else { return value }

        if intValue < minimumHeartRate {
            return String(minimumHeartRate)
        }

        if intValue > maximumHeartRate {
            return String(maximumHeartRate)
        }

        return String(intValue)
    }

    static func normalizeCaloriesOnSubmit(_ value: String) -> String {
        let digits = filterNumericInput(value)
        guard digits.isEmpty == false else { return "" }
        guard let intValue = Int(digits) else { return value }
        return String(max(intValue, 0))
    }
}
