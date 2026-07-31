import Foundation
import Testing
@testable import AscendApp

/// Regression cover for the activity detail screen's scroll stutter.
///
/// A 43-minute session stores one heart-rate sample per second, and the chart used
/// to emit one `LineMark` per sample - 2,603 marks, ~114 ms to render, seven 60 Hz
/// frames for a curve 362 points wide. These pin the cap and, just as importantly,
/// pin the fidelity: a cheaper chart that loses the climber's peak would be a worse
/// bug than the one being fixed.
struct HeartRateChartDownsamplingTests {
    private static let start = Date(timeIntervalSince1970: 1_750_300_000)

    /// A full-length session shaped like the recording: hard ramp, plateau, a dip,
    /// then interval spikes.
    private static func longSession() -> [HeartRateDataPoint] {
        var rate = 62.0
        return (0..<2_603).map { second in
            let elapsed = Double(second)
            let target: Double
            switch elapsed {
            case ..<90: target = 62 + elapsed * 1.05
            case ..<900: target = 150 + sin(elapsed / 70) * 6
            case ..<1_000: target = 128
            case ..<1_500: target = 165 + sin(elapsed / 50) * 5
            case ..<2_400: target = 170 + sin(elapsed / 45) * 6
            default: target = 150
            }
            rate += (target - rate) * 0.25
            return HeartRateDataPoint(
                timestamp: start.addingTimeInterval(elapsed),
                heartRate: Int(rate.rounded())
            )
        }
    }

    /// A strap that keeps cutting out: 13 seconds of 1 Hz capture, then a minute of
    /// silence, repeated. Every gap clears the dropout threshold, so each run becomes
    /// its own segment.
    private static func fragmentedSession(segmentCount: Int) -> [HeartRateDataPoint] {
        var samples: [HeartRateDataPoint] = []
        for segment in 0..<segmentCount {
            for second in 0..<13 {
                let elapsed = TimeInterval(segment * 72 + second)
                let heartRate: Int = 140 + (segment + second) % 23
                samples.append(
                    HeartRateDataPoint(
                        timestamp: start.addingTimeInterval(elapsed),
                        heartRate: heartRate
                    )
                )
            }
        }
        return samples
    }

    @Test
    func longSessionIsCappedToAPlottableNumberOfMarks() {
        let samples = Self.longSession()
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        #expect(samples.count == 2_603)
        #expect(dataSet.points.count <= HeartRateChartDataSet.maximumPlottedPointCount)
        #expect(dataSet.canPlotLine)
    }

    @Test
    func thinningKeepsTheRealPeakAndTrough() {
        let samples = Self.longSession()
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        let rawRates = samples.map(\.heartRate)
        let plottedRates = dataSet.points.map(\.heartRate)

        #expect(plottedRates.max() == rawRates.max())
        #expect(plottedRates.min() == rawRates.min())
    }

    @Test
    func thinningKeepsTheCurveAnchoredToBothEndsOfTheSession() {
        let samples = Self.longSession()
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        #expect(dataSet.points.first?.heartRate == samples.first?.heartRate)
        #expect(dataSet.points.last?.heartRate == samples.last?.heartRate)
        #expect(dataSet.points.first?.elapsed == 0)
        #expect(dataSet.points.last?.elapsed == 2_602)
    }

    @Test
    func plottedPointsStayInTimeOrder() {
        let dataSet = HeartRateChartDataSet(
            samples: Self.longSession(),
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        let elapsedValues = dataSet.points.map(\.elapsed)
        #expect(elapsedValues == elapsedValues.sorted())
    }

    /// Thinning runs inside each dropout segment, never across the series, because
    /// the gap threshold is derived from the samples' own median spacing - thinning
    /// first would rewrite that spacing and invent or hide dropouts.
    @Test
    func aDropoutSurvivesThinningAsASeparateSegment() {
        // Two 20-minute runs of 1 Hz capture with the strap silent in between.
        let firstRun = (0..<1_200).map { second in
            HeartRateDataPoint(
                timestamp: Self.start.addingTimeInterval(TimeInterval(second)),
                heartRate: 150 + second % 11
            )
        }
        let secondRun = (0..<1_200).map { second in
            HeartRateDataPoint(
                timestamp: Self.start.addingTimeInterval(TimeInterval(1_500 + second)),
                heartRate: 160 + second % 9
            )
        }

        let dataSet = HeartRateChartDataSet(
            samples: firstRun + secondRun,
            workoutStartTime: Self.start,
            workoutDuration: 2_700
        )

        #expect(dataSet.segments.count == 2)
        #expect(dataSet.points.count <= HeartRateChartDataSet.maximumPlottedPointCount)
        // Both runs still get marks - neither is thinned out of existence.
        #expect(dataSet.segments.allSatisfy { $0.points.count >= 2 })
        // The gap is still a gap: no plotted mark lands inside the silent window.
        let gapPoints = dataSet.points.filter { $0.elapsed > 1_210 && $0.elapsed < 1_490 }
        #expect(gapPoints.isEmpty)
    }

    /// A contiguous trace must not be split just because thinning spaced its marks out.
    @Test
    func aContinuousTraceStaysOneSegmentAfterThinning() {
        let dataSet = HeartRateChartDataSet(
            samples: Self.longSession(),
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        #expect(dataSet.segments.count == 1)
    }

    /// A fragmented trace still has to respect the cap. The budget is handed out
    /// after every segment has reserved its own endpoints, so 200 dropouts land
    /// exactly on the cap rather than blowing past it two marks at a time.
    @Test
    func aHeavilyFragmentedTraceStaysInsideTheCap() {
        let dataSet = HeartRateChartDataSet(
            samples: Self.fragmentedSession(segmentCount: 200),
            workoutStartTime: Self.start,
            workoutDuration: 14_400
        )

        #expect(dataSet.segments.count == 200)
        #expect(dataSet.points.count <= HeartRateChartDataSet.maximumPlottedPointCount)
        // No run is thinned out of existence - a segment that plotted nothing would
        // read as a longer dropout than actually happened.
        #expect(dataSet.segments.allSatisfy { $0.points.count == 2 })
    }

    /// Past `maximumPlottedPointCount / 2` segments the endpoints alone exceed the
    /// cap. This pins the documented worst case: two marks per segment, no more.
    @Test
    func aTraceWithMoreSegmentsThanBudgetKeepsOnlyEndpoints() {
        let dataSet = HeartRateChartDataSet(
            samples: Self.fragmentedSession(segmentCount: 250),
            workoutStartTime: Self.start,
            workoutDuration: 18_000
        )

        #expect(dataSet.segments.count == 250)
        #expect(dataSet.points.count == 500)
        #expect(dataSet.segments.allSatisfy { $0.points.count == 2 })
    }

    /// Thinning is a rendering concession, not a licence to misreport. The scrub
    /// readout resolves against the full series, so a sample the chart never plots
    /// is still the value shown when the climber's finger is over it.
    @Test
    func scrubbingResolvesASampleThatThinningRemovedFromTheChart() throws {
        let samples = Self.longSession()
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        #expect(dataSet.scrubPoints.count == samples.count)
        #expect(dataSet.points.count < dataSet.scrubPoints.count)

        let plottedIds = Set(dataSet.points.map(\.id))
        let thinnedAway = try #require(dataSet.scrubPoints.first { plottedIds.contains($0.id) == false })
        let resolved = try #require(dataSet.nearestScrubPoint(to: thinnedAway.elapsed))

        #expect(resolved == thinnedAway)
        #expect(resolved.heartRate == samples[thinnedAway.id].heartRate)
    }

    /// The "at m:ss" label has to name the touched moment, not the nearest surviving
    /// mark several seconds away.
    @Test
    func scrubbingResolvesTheSampleClosestToTheTouchedTime() throws {
        let dataSet = HeartRateChartDataSet(
            samples: Self.longSession(),
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )

        let resolved = try #require(dataSet.nearestScrubPoint(to: 1_234.4))
        #expect(resolved.elapsed == 1_234)
    }

    @Test
    func shortSessionsArePlottedSampleForSample() {
        let samples = (0..<120).map { second in
            HeartRateDataPoint(
                timestamp: Self.start.addingTimeInterval(TimeInterval(second)),
                heartRate: 140 + second % 7
            )
        }
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 120
        )

        #expect(dataSet.points.count == samples.count)
        #expect(dataSet.points.map(\.heartRate) == samples.map(\.heartRate))
    }
}
