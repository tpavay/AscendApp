enum WorkoutHeartRateEditPolicy {
    static func applyManualSummary(
        averageHeartRate: Int?,
        maximumHeartRate: Int?,
        to workout: Workout
    ) {
        let summaryChanged =
            workout.avgHeartRate != averageHeartRate ||
            workout.maxHeartRate != maximumHeartRate

        // The samples are the source data for their original summaries. Keeping
        // them after a manual override would leave the workout contradictory.
        if summaryChanged {
            workout.heartRateData = nil
        }

        workout.avgHeartRate = averageHeartRate
        workout.maxHeartRate = maximumHeartRate
    }
}
