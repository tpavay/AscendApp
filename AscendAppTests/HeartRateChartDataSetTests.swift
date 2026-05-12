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
