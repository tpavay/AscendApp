import Testing
@testable import AscendApp

struct WorkoutPlausibilityPolicyTests {
    @Test
    func rejectsImplausibleAverageStepPace() {
        #expect(WorkoutPlausibilityPolicy.hasPlausibleTotals(
            steps: 966,
            duration: 67.5363039970398
        ) == false)
    }

    @Test
    func acceptsStrongButPlausibleAverageStepPace() {
        #expect(WorkoutPlausibilityPolicy.hasPlausibleTotals(
            steps: 2_117,
            duration: 1_131.0771219730375
        ))
    }

    @Test
    func allowsWorkoutsWithoutStepTotals() {
        #expect(WorkoutPlausibilityPolicy.hasPlausibleTotals(
            steps: 0,
            duration: 1_800
        ))
    }
}
