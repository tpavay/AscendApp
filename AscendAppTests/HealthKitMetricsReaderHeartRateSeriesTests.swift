import Foundation
import Testing
@testable import AscendApp

struct HealthKitMetricsReaderHeartRateSeriesTests {
    @Test
    func mapsQuantitySeriesChildrenIntoSavedHeartRateSamples() {
        let start = makeDate(year: 2024, month: 4, day: 28, hour: 14, minute: 19)
        let end = start.addingTimeInterval(668)

        let samples = HealthKitMetricsReader.heartRateDataPoints(
            from: [
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(30), heartRate: 55, parentSampleId: "parent-1"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(300), heartRate: 153, parentSampleId: "parent-1"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(660), heartRate: 172, parentSampleId: "parent-1")
            ],
            within: start...end
        )

        #expect(samples == [
            HeartRateDataPoint(timestamp: start.addingTimeInterval(30), heartRate: 55),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(300), heartRate: 153),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(660), heartRate: 172)
        ])
    }

    @Test
    func dropsInvalidAndOutOfWindowQuantitySeriesChildren() {
        let start = makeDate(year: 2024, month: 5, day: 9, hour: 23, minute: 21)
        let end = start.addingTimeInterval(1_111)

        let samples = HealthKitMetricsReader.heartRateDataPoints(
            from: [
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(-1), heartRate: 95, parentSampleId: "before"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(10), heartRate: 104, parentSampleId: "parent-1"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(900), heartRate: 170, parentSampleId: "parent-2"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(1_112), heartRate: 151, parentSampleId: "after"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(500), heartRate: 0, parentSampleId: "invalid")
            ],
            within: start...end
        )

        #expect(samples == [
            HeartRateDataPoint(timestamp: start.addingTimeInterval(10), heartRate: 104),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(900), heartRate: 170)
        ])
    }

    @Test
    func sortsQuantitySeriesChildrenBeforeSaving() {
        let start = makeDate(year: 2026, month: 1, day: 3, hour: 14, minute: 47)
        let end = start.addingTimeInterval(3_609)

        let samples = HealthKitMetricsReader.heartRateDataPoints(
            from: [
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(1_000), heartRate: 160, parentSampleId: "parent-2"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(5), heartRate: 79, parentSampleId: "parent-1"),
                HeartRateSeriesPoint(timestamp: start.addingTimeInterval(3_600), heartRate: 167, parentSampleId: "parent-4")
            ],
            within: start...end
        )

        #expect(samples.map(\.heartRate) == [79, 160, 167])
        #expect(samples.map(\.timestamp) == [
            start.addingTimeInterval(5),
            start.addingTimeInterval(1_000),
            start.addingTimeInterval(3_600)
        ])
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
