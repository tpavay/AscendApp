import Foundation

enum WorkoutInputValidation {
    static let nameMaxLength = 120
    static let notesMaxLength = 5_000
    static let minimumHeartRate = 25
    static let maximumHeartRate = 230

    static func isValidOptionalMetric(_ value: String) -> Bool {
        guard value.isEmpty == false else { return true }
        guard let intValue = Int(value) else { return false }
        return intValue >= 0
    }

    static func isValidWorkoutTotals(
        metricValue: String,
        preferredMetric: WorkoutMetric,
        stepsPerFloor: Int,
        durationHours: Int,
        durationMinutes: Int,
        durationSeconds: Int
    ) -> Bool {
        let enteredValue = Int(metricValue) ?? 0
        let totalDuration = TimeInterval(durationHours * 3_600 + durationMinutes * 60 + durationSeconds)
        let steps = preferredMetric == .steps
            ? enteredValue
            : Workout.floorsToSteps(enteredValue, stepsPerFloor: stepsPerFloor)

        return WorkoutPlausibilityPolicy.hasPlausibleTotals(
            steps: steps,
            duration: totalDuration
        )
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
