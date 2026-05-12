import Testing
@testable import AscendApp

struct WorkoutInputValidationTests {
    @Test
    func workoutNameAllowsUpToConfiguredLimit() {
        let validName = String(repeating: "A", count: WorkoutInputValidation.nameMaxLength)
        let invalidName = validName + "A"

        #expect(WorkoutInputValidation.isValidWorkoutName(validName))
        #expect(WorkoutInputValidation.isValidWorkoutName(""))
        #expect(WorkoutInputValidation.isValidWorkoutName(invalidName) == false)
    }

    @Test
    func notesAllowUpToConfiguredLimit() {
        let validNotes = String(repeating: "N", count: WorkoutInputValidation.notesMaxLength)
        let invalidNotes = validNotes + "N"

        #expect(WorkoutInputValidation.isValidNotes(validNotes))
        #expect(WorkoutInputValidation.isValidNotes(invalidNotes) == false)
    }

    @Test
    func optionalMetricRequiresNonNegativeInteger() {
        #expect(WorkoutInputValidation.isValidOptionalMetric(""))
        #expect(WorkoutInputValidation.isValidOptionalMetric("0"))
        #expect(WorkoutInputValidation.isValidOptionalMetric("42"))
        #expect(WorkoutInputValidation.isValidOptionalMetric("-1") == false)
        #expect(WorkoutInputValidation.isValidOptionalMetric("abc") == false)
    }

    @Test
    func workoutTotalsRejectImplausibleAverageStepPace() {
        #expect(WorkoutInputValidation.isValidWorkoutTotals(
            metricValue: "966",
            preferredMetric: .steps,
            stepsPerFloor: 16,
            durationHours: 0,
            durationMinutes: 1,
            durationSeconds: 7
        ) == false)

        #expect(WorkoutInputValidation.isValidWorkoutTotals(
            metricValue: "2117",
            preferredMetric: .steps,
            stepsPerFloor: 16,
            durationHours: 0,
            durationMinutes: 18,
            durationSeconds: 51
        ))
    }

    @Test
    func heartRateNormalizationClampsToSupportedRange() {
        #expect(WorkoutInputValidation.normalizeHeartRateOnSubmit("") == "")
        #expect(WorkoutInputValidation.normalizeHeartRateOnSubmit("12") == "25")
        #expect(WorkoutInputValidation.normalizeHeartRateOnSubmit("145") == "145")
        #expect(WorkoutInputValidation.normalizeHeartRateOnSubmit("999") == "230")
    }

    @Test
    func caloriesNormalizationKeepsOnlyNonNegativeDigits() {
        #expect(WorkoutInputValidation.normalizeCaloriesOnSubmit("") == "")
        #expect(WorkoutInputValidation.normalizeCaloriesOnSubmit("450") == "450")
        #expect(WorkoutInputValidation.filterNumericInput("-12a3") == "123")
    }
}
