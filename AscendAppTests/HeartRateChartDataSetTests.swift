import Foundation
import Testing
@testable import AscendApp

struct HeartRateChartDataSetTests {
    @Test
    func oneSampleIsNotEnoughForLineChart() {
        let start = makeDate(year: 2024, month: 5, day: 12, hour: 14, minute: 17)
        let dataSet = HeartRateChartDataSet(
            samples: [
                HeartRateDataPoint(timestamp: start.addingTimeInterval(5), heartRate: 154)
            ],
            workoutStartTime: start,
            workoutDuration: 1_292
        )

        #expect(dataSet.points.count == 1)
        #expect(dataSet.canPlotLine == false)
        #expect(dataSet.heartRateRange == 149...159)
    }

    @Test
    func twoSparseSamplesAreNotEnoughForLineChart() {
        let start = makeDate(year: 2024, month: 5, day: 9, hour: 23, minute: 21)
        let dataSet = HeartRateChartDataSet(
            samples: [
                HeartRateDataPoint(timestamp: start.addingTimeInterval(10), heartRate: 153),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(1_010), heartRate: 164)
            ],
            workoutStartTime: start,
            workoutDuration: 1_111
        )

        #expect(dataSet.points.count == 2)
        #expect(dataSet.canPlotLine == false)
        #expect(dataSet.duration == 1_111)
    }

    /// A Garmin or Whoop that wrote a handful of readings has answered sparsely, not failed.
    /// The stand-in copy has to say which of those two happened.
    @Test
    func sparseSeriesReportsItsCountInsteadOfReadingAsAFailedLoad() {
        #expect(
            HeartRateChartView.unavailableChartMessage(sampleCount: 0)
                == "No heart-rate samples for this climb"
        )
        #expect(
            HeartRateChartView.unavailableChartMessage(sampleCount: 1)
                == "Your wearable logged one reading for this climb - too few to chart"
        )
        #expect(
            HeartRateChartView.unavailableChartMessage(sampleCount: 2)
                == "Your wearable logged 2 readings for this climb - too few to chart"
        )
    }

    @Test
    func threeSamplesCanPlotAcrossWorkoutDuration() {
        let start = makeDate(year: 2026, month: 5, day: 10, hour: 15, minute: 5)
        let dataSet = HeartRateChartDataSet(
            samples: [
                HeartRateDataPoint(timestamp: start.addingTimeInterval(5), heartRate: 118),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(300), heartRate: 132),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(600), heartRate: 145)
            ],
            workoutStartTime: start,
            workoutDuration: 780
        )

        #expect(dataSet.canPlotLine)
        #expect(dataSet.points.map(\.elapsed) == [5.0, 300.0, 600.0])
        #expect(dataSet.duration == 780)
    }

    @Test
    func strapDropoutBreaksTheLineInsteadOfInterpolatingIt() {
        let start = makeDate(year: 2026, month: 7, day: 4, hour: 6, minute: 30)
        let beforeDrop = (0..<20).map { second in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(second)),
                heartRate: 140 + second % 3
            )
        }
        let afterReconnect = (0..<20).map { second in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(320 + second)),
                heartRate: 150 + second % 3
            )
        }
        let dataSet = HeartRateChartDataSet(
            samples: beforeDrop + afterReconnect,
            workoutStartTime: start,
            workoutDuration: 600
        )

        #expect(dataSet.canPlotLine)
        #expect(dataSet.segments.count == 2)
        #expect(dataSet.segments.map(\.points.count) == [20, 20])
        #expect(dataSet.segments[0].points.last?.elapsed == 19)
        #expect(dataSet.segments[1].points.first?.elapsed == 320)
        #expect(dataSet.segments.map(\.id) == [0, 1])
    }

    @Test
    func steadyLiveCadenceStaysOneUnbrokenSegment() {
        let start = makeDate(year: 2026, month: 7, day: 4, hour: 7, minute: 15)
        let samples = (0..<60).map { second in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(second)),
                heartRate: 130 + second % 5
            )
        }
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: start,
            workoutDuration: 300
        )

        #expect(dataSet.segments.count == 1)
        #expect(dataSet.segments.first?.points.count == 60)
    }

    @Test
    func sparseImportedSamplesAreNotShatteredByTheirOwnCadence() {
        let start = makeDate(year: 2026, month: 7, day: 4, hour: 8, minute: 0)
        let samples = (0..<10).map { index in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(index * 300)),
                heartRate: 120 + index
            )
        }
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: start,
            workoutDuration: 3_000
        )

        #expect(dataSet.segments.count == 1)
        #expect(dataSet.segments.first?.points.count == 10)
    }

    @Test
    func aSingleSampleAfterADropoutSurvivesAsItsOwnSegment() {
        let start = makeDate(year: 2026, month: 7, day: 4, hour: 9, minute: 45)
        var samples = (0..<15).map { second in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(second)),
                heartRate: 145
            )
        }
        samples.append(
            HeartRateDataPoint(timestamp: start.addingTimeInterval(400), heartRate: 158)
        )
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: start,
            workoutDuration: 600
        )

        #expect(dataSet.segments.count == 2)
        #expect(dataSet.segments.last?.points.map(\.heartRate) == [158])
    }

    @Test
    func emptyAndSingleSampleSeriesProduceSafeSegments() {
        let start = makeDate(year: 2026, month: 7, day: 4, hour: 10, minute: 5)
        let empty = HeartRateChartDataSet(
            samples: [],
            workoutStartTime: start,
            workoutDuration: 600
        )
        let single = HeartRateChartDataSet(
            samples: [HeartRateDataPoint(timestamp: start, heartRate: 132)],
            workoutStartTime: start,
            workoutDuration: 600
        )

        #expect(empty.segments.isEmpty)
        #expect(single.segments.count == 1)
        #expect(single.segments.first?.points.count == 1)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
