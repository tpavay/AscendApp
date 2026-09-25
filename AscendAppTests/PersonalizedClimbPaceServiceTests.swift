import Foundation
import Testing
@testable import AscendApp

/// The one estimate every climb surface renders: the climber's all-time aggregate pace
/// once they have climbed, the app's existing default pace before that (#600).
@MainActor
struct PersonalizedClimbPaceServiceTests {
    @Test
    func theAverageIsAnAggregateRateNotAMeanOfPerClimbRates() throws {
        // 1,000 steps in 10 min (100 SPM) and 1,000 steps in 40 min (25 SPM): the mean of
        // the two rates is 62.5, the aggregate is 2,000 / 50 = 40.
        let workouts = [
            workout(steps: 1_000, minutes: 10),
            workout(steps: 1_000, minutes: 40),
        ]

        let average = try #require(PersonalizedClimbPaceService.allTimeAverageSPM(workouts: workouts))
        #expect(abs(average - 40) < 0.0001)
        #expect(PersonalizedClimbPaceService.effectiveSPM(workouts: workouts) == 40)
        // Empire State's 1,576 real stairs at 40 SPM = 39.4 -> ~39 min.
        #expect(
            PersonalizedClimbPaceService.estimatedTimeText(
                forStepCount: Climb.preview.referenceStepCount,
                workouts: workouts
            ) == "~39 min"
        )
    }

    @Test
    func aClimberWithNoClimbsGetsTheExistingDefaultPace() {
        let defaultSPM = SettingsManager.shared.effectiveBaseLevelSPM
        #expect(defaultSPM > 0)
        #expect(PersonalizedClimbPaceService.allTimeAverageSPM(workouts: []) == nil)
        #expect(PersonalizedClimbPaceService.effectiveSPM(workouts: []) == defaultSPM)
        #expect(
            PersonalizedClimbPaceService.estimatedTimeText(forStepCount: 1_576, workouts: [])
                == ClimbEstimatedTimeFormatter.estimatedTimeText(for: 1_576, spm: defaultSPM)
        )
    }

    @Test
    func aHistoryWithNoUsableTimeOrStepsFallsBackToTheDefault() {
        let defaultSPM = SettingsManager.shared.effectiveBaseLevelSPM
        #expect(PersonalizedClimbPaceService.effectiveSPM(workouts: [workout(steps: 900, minutes: 0)]) == defaultSPM)
        #expect(PersonalizedClimbPaceService.effectiveSPM(workouts: [workout(steps: 0, minutes: 12)]) == defaultSPM)
    }

    @Test
    func aZeroOrTinyClimbNeverReadsZeroMinutes() {
        let workouts = [workout(steps: 3_000, minutes: 30)]
        #expect(PersonalizedClimbPaceService.estimatedTimeText(forStepCount: 0, workouts: workouts) == "~1 min")
        #expect(PersonalizedClimbPaceService.estimatedTimeText(forStepCount: 5, workouts: workouts) == "~1 min")
        #expect(PersonalizedClimbPaceService.estimatedTimeText(forStepCount: 0, workouts: []) == "~1 min")
    }

    @Test
    func longClimbsFormatInHoursAndMinutes() {
        let workouts = [workout(steps: 6_000, minutes: 100)]  // 60 SPM
        #expect(PersonalizedClimbPaceService.estimatedTimeText(forStepCount: 3_600, workouts: workouts) == "~1h")
        #expect(PersonalizedClimbPaceService.estimatedTimeText(forStepCount: 5_100, workouts: workouts) == "~1h 25m")
    }

    /// Profile's "Avg SPM" and the estimate read the same number, so the refactor of
    /// `ProfileSnapshotBuilder` onto the shared formula must not move what Profile shows.
    @Test
    func profileAverageSPMIsTheSameNumberTheEstimateUses() {
        let workouts = [
            workout(steps: 1_234, minutes: 17.3),
            workout(steps: 2_345, minutes: 29.9),
            workout(steps: 812, minutes: 11.05),
        ]
        let stats = ProfileSnapshotBuilder.statsSnapshot(
            workouts: workouts,
            completedAttempts: [],
            completedCount: 0,
            achievements: .zero
        )

        let lifetimeSteps = workouts.reduce(0) { $0 + $1.steps }
        let lifetimeSeconds = Int(workouts.reduce(0.0) { $0 + $1.duration }.rounded())
        let preRefactorFormula = Double(lifetimeSteps) / (Double(lifetimeSeconds) / 60.0)

        #expect(stats.averageStepsPerMinute == preRefactorFormula)
        #expect(stats.averageStepsPerMinute == PersonalizedClimbPaceService.allTimeAverageSPM(workouts: workouts))
        #expect(
            ProfileSnapshotBuilder.statsSnapshot(
                workouts: [],
                completedAttempts: [],
                completedCount: 0,
                achievements: .zero
            ).averageStepsPerMinute == 0
        )
    }

    @Test
    func climbDetailEstimateDefaultsWithoutAThreadedPaceAndUsesTheRowsPaceWhenGiven() {
        // Deep links, notifications and Today's Climb pass nothing: the default pace.
        let defaultViewModel = ClimbDetailViewModel(climb: .preview)
        #expect(
            defaultViewModel.estimatedTimeText
                == PersonalizedClimbPaceService.estimatedTimeText(forStepCount: Climb.preview.referenceStepCount, workouts: [])
        )

        // Home and Browse thread the pace their rows already computed.
        let workouts = [workout(steps: 4_000, minutes: 50)]  // 80 SPM
        let viewModel = ClimbDetailViewModel(
            climb: .preview,
            effectiveSPM: PersonalizedClimbPaceService.effectiveSPM(workouts: workouts)
        )
        // 1,576 / 80 = 19.7 -> ~20 min, the same text the Home row renders for this climb.
        #expect(viewModel.estimatedTimeText == "~20 min")
        #expect(
            viewModel.estimatedTimeText
                == PersonalizedClimbPaceService.estimatedTimeText(forStepCount: Climb.preview.referenceStepCount, workouts: workouts)
        )
    }

    private func workout(steps: Int, minutes: Double) -> Workout {
        Workout(duration: minutes * 60, steps: steps, floors: steps / 16, source: .headphoneMotion)
    }
}
