import Foundation
import Testing
@testable import AscendApp

struct WorkoutHeartRatePlausibilityTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func untouchedSeriesKeepsTheSourceSummary() {
        let samples = [
            HeartRateDataPoint(timestamp: start, heartRate: 121),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 148)
        ]

        let normalized = WorkoutHeartRatePlausibility.normalized(
            samples: samples,
            average: 130,
            maximum: 151
        )

        #expect(normalized.samples == samples)
        #expect(normalized.average == 130)
        #expect(normalized.maximum == 151)
    }

    @Test
    func droppingAPointRecomputesTheSummaryFromWhatSurvived() {
        let retained = [
            HeartRateDataPoint(timestamp: start, heartRate: 121),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(180), heartRate: 148)
        ]

        let normalized = WorkoutHeartRatePlausibility.normalized(
            samples: [
                retained[0],
                HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 512),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(120), heartRate: 0),
                retained[1]
            ],
            average: 195,
            maximum: 512
        )

        #expect(normalized.samples == retained)
        #expect(normalized.average == 135)
        #expect(normalized.maximum == 148)
    }

    @Test
    func anOutOfRangeSourceSummaryIsReplacedEvenWhenTheSeriesIsClean() {
        let samples = [
            HeartRateDataPoint(timestamp: start, heartRate: 121),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 148)
        ]

        let normalized = WorkoutHeartRatePlausibility.normalized(
            samples: samples,
            average: 130,
            maximum: 512
        )

        #expect(normalized.samples == samples)
        #expect(normalized.average == 130)
        #expect(normalized.maximum == 148)
    }

    @Test
    func aMissingSourceSummaryStaysMissing() {
        let samples = [HeartRateDataPoint(timestamp: start, heartRate: 121)]

        let normalized = WorkoutHeartRatePlausibility.normalized(
            samples: samples,
            average: nil,
            maximum: nil
        )

        #expect(normalized.samples == samples)
        #expect(normalized.average == nil)
        #expect(normalized.maximum == nil)
    }

    @Test
    func aSeriesWithNoUsablePointsClearsTheSummaryToo() {
        let normalized = WorkoutHeartRatePlausibility.normalized(
            samples: [
                HeartRateDataPoint(timestamp: start, heartRate: 0),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 401)
            ],
            average: 200,
            maximum: 401
        )

        #expect(normalized.samples.isEmpty)
        #expect(normalized.average == nil)
        #expect(normalized.maximum == nil)
    }

    @Test
    func liveCaptureBufferRejectsOutOfRangeReadingsAtIntake() {
        var buffer = HeartRateSessionSampleBuffer(minimumCaptureInterval: 0)
        let readings = [128, 0, 401, 400, 143]

        for (offset, beatsPerMinute) in readings.enumerated() {
            buffer.record(
                beatsPerMinute: beatsPerMinute,
                capturedAt: start.addingTimeInterval(Double(offset) * 5),
                sessionStartedAt: start,
                sessionElapsed: Double(offset) * 5
            )
        }

        #expect(buffer.samples.map(\.heartRate) == [128, 400, 143])
    }
}
