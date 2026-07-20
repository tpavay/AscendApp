import Foundation

struct HeartRateTraceCoverage: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case complete
        case partial
    }

    let status: Status
    let sampleCount: Int
    let sessionDurationSeconds: TimeInterval
    let coveredDurationSeconds: TimeInterval
    let coverageFraction: Double
    let firstSampleElapsedSeconds: TimeInterval
    let lastSampleElapsedSeconds: TimeInterval
    let longestUncoveredDurationSeconds: TimeInterval

    init?(
        samples: [HeartRateDataPoint],
        sessionStartedAt: Date,
        sessionDuration: TimeInterval
    ) {
        let duration = max(sessionDuration, 1)
        let elapsedSamples = samples
            .filter { $0.heartRate > 0 }
            .map { min(max($0.timestamp.timeIntervalSince(sessionStartedAt), 0), duration) }
            .sorted()
        guard let firstSample = elapsedSamples.first,
              let lastSample = elapsedSamples.last else {
            return nil
        }

        let expectedSampleInterval: TimeInterval = 1
        let leadingUncovered = max(firstSample - expectedSampleInterval, 0)
        let trailingUncovered = max(duration - lastSample - expectedSampleInterval, 0)
        let internalUncovered = zip(elapsedSamples, elapsedSamples.dropFirst()).map { previous, current in
            max(current - previous - expectedSampleInterval, 0)
        }
        let uncoveredDuration = min(
            leadingUncovered + trailingUncovered + internalUncovered.reduce(0, +),
            duration
        )
        let coveredDuration = max(duration - uncoveredDuration, 0)
        let fraction = min(max(coveredDuration / duration, 0), 1)
        let longestUncovered = max(
            leadingUncovered,
            trailingUncovered,
            internalUncovered.max() ?? 0
        )

        self.status = fraction >= 0.95 && longestUncovered <= 5 ? .complete : .partial
        self.sampleCount = elapsedSamples.count
        self.sessionDurationSeconds = duration
        self.coveredDurationSeconds = coveredDuration
        self.coverageFraction = fraction
        self.firstSampleElapsedSeconds = firstSample
        self.lastSampleElapsedSeconds = lastSample
        self.longestUncoveredDurationSeconds = longestUncovered
    }
}
