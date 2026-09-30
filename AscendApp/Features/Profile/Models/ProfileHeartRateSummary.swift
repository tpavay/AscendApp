import Foundation

/// The two heart-rate numbers a climber's public profile carries, and nothing finer.
///
/// Another climber's samples and per-climb heart rate stay private; only these aggregates are
/// published to `profile_stats`, derived once at publish time from the climber's own climbs.
/// `scripts/lib/profile-heart-rate.mjs` is the same derivation for the backfill, and
/// `SharedTestVectors/profile-heart-rate-summary-vector.json` holds the two to one answer.
struct ProfileHeartRateSummary: Equatable, Sendable {
    /// One climb's contribution: its duration and the heart rate already summarised onto it.
    struct Climb: Equatable, Sendable {
        let durationSeconds: TimeInterval
        let averageBpm: Int?
        let maxBpm: Int?
    }

    /// Duration-weighted mean of each climb's own average heart rate, over the climbs that
    /// carry one - a 40-minute climb counts four times a 10-minute one, so the number reads
    /// as "average heart rate while climbing" rather than an average of averages.
    let averageBpm: Int?
    /// The highest heart rate recorded on any climb.
    let maxBpm: Int?

    /// Wider than any human heart and narrower than a sensor fault, so one garbage reading
    /// cannot become a public number. `firestore.rules` enforces the same bounds.
    static let plausibleBpm: ClosedRange<Int> = 25...250

    init?(averageBpm: Int?, maxBpm: Int?) {
        let average = averageBpm.flatMap { Self.plausibleBpm.contains($0) ? $0 : nil }
        let max = maxBpm.flatMap { Self.plausibleBpm.contains($0) ? $0 : nil }
        guard average != nil || max != nil else { return nil }
        self.averageBpm = average
        self.maxBpm = max
    }

    /// `nil` when no climb carries a plausible heart rate - the comparison hides the rows.
    static func derive(from climbs: [Climb]) -> ProfileHeartRateSummary? {
        var weightedBeats = 0.0
        var weightedSeconds = 0.0
        var highest: Int?

        for climb in climbs {
            if let average = climb.averageBpm,
               plausibleBpm.contains(average),
               climb.durationSeconds > 0 {
                weightedBeats += Double(average) * climb.durationSeconds
                weightedSeconds += climb.durationSeconds
            }
            if let max = climb.maxBpm, plausibleBpm.contains(max) {
                highest = Swift.max(highest ?? max, max)
            }
        }

        let average = weightedSeconds > 0
            ? Int((weightedBeats / weightedSeconds).rounded())
            : nil
        return ProfileHeartRateSummary(averageBpm: average, maxBpm: highest)
    }
}
