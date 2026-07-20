struct LiveHeartRateWorkoutSummary: Equatable, Sendable {
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let timeSeries: [HeartRateDataPoint]?
}
