import Foundation
import Testing
@testable import AscendApp

/// What onboarding's "We found your climbs" says back, built from Health's workouts alone: the
/// totals, the Everest line, the best hour and the usual climb. Pure arithmetic over snapshots, so
/// every rule the screen states is pinned here and not read off a photograph.
struct HealthHistorySummaryTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func workout(
        daysAgo: Double,
        minutes: Double = 40,
        steps: Int? = 3_000,
        id: UUID = UUID()
    ) -> HealthWorkoutSnapshot {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return HealthWorkoutSnapshot(
            uuid: id,
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            steps: steps
        )
    }

    private static func summary(_ workouts: [HealthWorkoutSnapshot]) -> HealthHistorySummary {
        HealthHistorySummary.make(from: workouts, now: now)
    }

    // MARK: - Totals

    @Test
    func theTotalsCountEveryWorkoutAndOnlyTheStepsHealthReported() {
        let summary = Self.summary([
            Self.workout(daysAgo: 1, minutes: 30, steps: 2_000),
            Self.workout(daysAgo: 2, minutes: 45, steps: nil),
            Self.workout(daysAgo: 3, minutes: 15, steps: 1_000)
        ])

        #expect(summary.workoutCount == 3)
        #expect(summary.totalDuration == 90 * 60)
        #expect(summary.workoutsWithSteps == 2)
        #expect(summary.knownSteps == 3_000, "a workout with no steps adds nothing: unknown is never zero")
    }

    @Test
    func noWorkoutsIsAnEmptySummary() {
        let summary = Self.summary([])

        #expect(summary.isEmpty)
        #expect(summary.usualClimb == nil)
        #expect(summary.bestHourSteps == nil)
    }

    @Test
    func aWorkoutThatCannotBeAClimbIsNotFound() {
        let summary = Self.summary([
            Self.workout(daysAgo: 1, minutes: 0.01, steps: 10),
            Self.workout(daysAgo: 2, minutes: 25 * 60, steps: 4_000),
            Self.workout(daysAgo: 3, minutes: 30, steps: 2_500)
        ])

        #expect(summary.workoutCount == 1, "under a second and over a day are never filed, so never promised")
    }

    @Test
    func stepsNoStairStepperProducesAreDroppedLikeAnImportDropsThem() {
        // 12,000 steps in 20 minutes is 600 a minute: the import would keep the workout and drop the number.
        let summary = Self.summary([Self.workout(daysAgo: 1, minutes: 20, steps: 12_000)])

        #expect(summary.workoutCount == 1)
        #expect(summary.workoutsWithSteps == 0)
        #expect(summary.knownSteps == 0)
    }

    @Test
    func theHeadlineLeadsWithStepsOnlyWhenHalfTheWorkoutsReportThem() {
        let half = Self.summary([
            Self.workout(daysAgo: 1, steps: 3_000),
            Self.workout(daysAgo: 2, steps: nil)
        ])
        let fewer = Self.summary([
            Self.workout(daysAgo: 1, steps: 3_000),
            Self.workout(daysAgo: 2, steps: nil),
            Self.workout(daysAgo: 3, steps: nil)
        ])
        let none = Self.summary([Self.workout(daysAgo: 1, steps: nil)])

        #expect(half.leadsWithSteps)
        #expect(!fewer.leadsWithSteps)
        #expect(!none.leadsWithSteps)
    }

    @Test(arguments: [
        (count: 1, minutes: 0.4, text: "1 min"),
        (count: 1, minutes: 41.0, text: "41 min"),
        (count: 1, minutes: 60.0, text: "1 hour"),
        (count: 146, minutes: 60.0, text: "146 hours")
    ])
    func theTotalTimeIsSaidInMinutesUnderAnHourAndHoursAfter(count: Int, minutes: Double, text: String) {
        let workouts = (0..<count).map { Self.workout(daysAgo: Double($0 + 1), minutes: minutes, steps: nil) }

        #expect(Self.summary(workouts).totalDurationText == text)
    }

    @Test
    func theIdentifiersAreTheWorkoutsAnImportWouldFile() {
        let first = UUID()
        let second = UUID()
        let summary = Self.summary([
            Self.workout(daysAgo: 1, id: first),
            Self.workout(daysAgo: 2, id: second)
        ])

        #expect(Set(summary.workoutIDs) == [first.uuidString, second.uuidString])
    }

    // MARK: - Best hour

    @Test
    func theBestHourIsReadOnlyFromWorkoutsOfAnHourOrMoreThatReportSteps() {
        let summary = Self.summary([
            Self.workout(daysAgo: 1, minutes: 30, steps: 9_000),
            Self.workout(daysAgo: 2, minutes: 120, steps: 12_000),
            Self.workout(daysAgo: 3, minutes: 60, steps: 4_000),
            Self.workout(daysAgo: 4, minutes: 90, steps: nil)
        ])

        #expect(summary.bestHourSteps == 6_000, "the 120 minute workout's steps spread evenly over an hour")
    }

    @Test
    func noWorkoutLongEnoughMeansNoBestHour() {
        let summary = Self.summary([Self.workout(daysAgo: 1, minutes: 59, steps: 5_000)])

        #expect(summary.bestHourSteps == nil)
    }

    // MARK: - Usual climb

    @Test
    func theUsualClimbIsTheMedianOfTheLastThirtyDays() {
        let summary = Self.summary([
            Self.workout(daysAgo: 2, minutes: 30, steps: 2_000),
            Self.workout(daysAgo: 9, minutes: 40, steps: 3_000),
            Self.workout(daysAgo: 20, minutes: 50, steps: 5_000),
            Self.workout(daysAgo: 200, minutes: 90, steps: 20_000)
        ])

        #expect(summary.usualClimb == HealthHistorySummary.UsualClimb(steps: 3_000, minutes: 40))
    }

    @Test
    func withNothingInTheLastThirtyDaysTheUsualClimbReadsEverything() {
        let summary = Self.summary([
            Self.workout(daysAgo: 100, minutes: 30, steps: 2_000),
            Self.workout(daysAgo: 200, minutes: 50, steps: 4_000)
        ])

        #expect(summary.usualClimb == HealthHistorySummary.UsualClimb(steps: 3_000, minutes: 40))
    }

    @Test
    func theUsualClimbIsMinutesAloneWhenNoWorkoutInItReportedSteps() {
        let summary = Self.summary([
            Self.workout(daysAgo: 2, minutes: 41, steps: nil),
            Self.workout(daysAgo: 4, minutes: 39, steps: nil),
            Self.workout(daysAgo: 6, minutes: 43, steps: nil)
        ])

        #expect(summary.usualClimb == HealthHistorySummary.UsualClimb(steps: nil, minutes: 41))
    }

    @Test
    func aWorkoutWithoutStepsNeverPullsTheUsualStepsDown() {
        let summary = Self.summary([
            Self.workout(daysAgo: 1, minutes: 40, steps: 3_200),
            Self.workout(daysAgo: 2, minutes: 40, steps: nil),
            Self.workout(daysAgo: 3, minutes: 40, steps: nil)
        ])

        #expect(summary.usualClimb?.steps == 3_200)
    }

    // MARK: - Everest

    @Test
    func everestIsFlooredFromKnownStepsOnly() {
        #expect(HealthHistoryComparison.make(knownSteps: 698_240, climbs: [])?.timesOver == 14)
        #expect(HealthHistoryComparison.make(knownSteps: 698_240, climbs: [])?.isEverest == true)
        #expect(HealthHistoryComparison.make(knownSteps: 48_664, climbs: [])?.timesOver == 1)
        #expect(HealthHistoryComparison.make(knownSteps: 97_327, climbs: [])?.timesOver == 1)
        #expect(HealthHistoryComparison.make(knownSteps: 97_328, climbs: [])?.timesOver == 2)
    }

    @Test
    func noKnownStepsLeavesTheCardOut() {
        #expect(HealthHistoryComparison.make(knownSteps: 0, climbs: [Climb.preview]) == nil)
    }

    @Test
    func underOneEverestItComparesWithTheTallestClimbCovered() throws {
        let empire = Climb.preview
        let comparison = try #require(HealthHistoryComparison.make(knownSteps: 5_000, climbs: [empire]))

        #expect(comparison.name == "Empire State Building")
        #expect(comparison.isEverest == false)
        #expect(comparison.timesOver == 3, "5,000 over 1,576 stairs")
        #expect(comparison.kicker == "That's the Empire State Building")
    }

    @Test
    func underEveryClimbThereIsNoCardAndAComingSoonClimbIsNeverTheComparison() {
        #expect(HealthHistoryComparison.make(knownSteps: 100, climbs: [Climb.preview]) == nil)
        #expect(HealthHistoryComparison.make(knownSteps: 5_000, climbs: [Climb.previewComingSoon]) == nil)
    }

    @Test
    func oneTimeOverReadsAsOneTimeAndThePeaksStopAtWhatARowHolds() throws {
        let one = try #require(HealthHistoryComparison.make(knownSteps: 50_000, climbs: []))
        let many = try #require(HealthHistoryComparison.make(knownSteps: 48_664 * 90, climbs: []))

        #expect(one.timesOverText == "1 time over.")
        #expect(one.peakCount == 1)
        #expect(many.timesOverText == "90 times over.")
        #expect(many.peakCount == HealthHistoryComparison.maximumPeaks)
    }

    @Test
    func theEverestStepCountIsTheCatalogues() throws {
        let url = try #require(Bundle.main.url(forResource: "climbs", withExtension: "json"))
        let climbs = try JSONDecoder().decode([Climb].self, from: Data(contentsOf: url))
        let everest = try #require(climbs.first { $0.id == "mount-everest" })

        #expect(everest.totalSteps == HealthHistoryComparison.everestSteps)
    }
}
