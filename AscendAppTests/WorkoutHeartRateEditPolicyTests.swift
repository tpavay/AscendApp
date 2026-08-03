import Foundation
import Testing
@testable import AscendApp

struct WorkoutHeartRateEditPolicyTests {
    @Test
    func manualSummaryEditDiscardsIncompatibleSampleSeries() {
        let startedAt = Date(timeIntervalSince1970: 1_753_776_000)
        let workout = Workout(
            duration: 1_800,
            steps: 1_800,
            floors: 113,
            avgHeartRate: 140,
            maxHeartRate: 168,
            heartRateTimeSeries: [
                HeartRateDataPoint(timestamp: startedAt, heartRate: 132),
                HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(600), heartRate: 148),
                HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(1_200), heartRate: 168)
            ],
            source: .appleHealth
        )

        WorkoutHeartRateEditPolicy.applyManualSummary(
            averageHeartRate: 150,
            maximumHeartRate: 168,
            to: workout
        )

        #expect(workout.avgHeartRate == 150)
        #expect(workout.maxHeartRate == 168)
        #expect(
            workout.heartRateTimeSeries.isEmpty,
            "Manual summary values must not coexist with a sampled series that produces different values."
        )
    }

    @Test
    func unchangedSummaryPreservesCompatibleSampleSeries() {
        let startedAt = Date(timeIntervalSince1970: 1_753_776_000)
        let samples = [
            HeartRateDataPoint(timestamp: startedAt, heartRate: 132),
            HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(600), heartRate: 148),
            HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(1_200), heartRate: 168)
        ]
        let workout = Workout(
            duration: 1_800,
            steps: 1_800,
            floors: 113,
            avgHeartRate: 140,
            maxHeartRate: 168,
            heartRateTimeSeries: samples,
            source: .appleHealth
        )

        WorkoutHeartRateEditPolicy.applyManualSummary(
            averageHeartRate: 140,
            maximumHeartRate: 168,
            to: workout
        )

        #expect(workout.heartRateTimeSeries == samples)
    }
}
