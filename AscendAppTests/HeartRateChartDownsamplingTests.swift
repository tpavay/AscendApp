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
    ///
    /// Each run's trough and peak sit in its interior, never at its endpoints, so a
    /// thinning pass that kept only endpoints would visibly lose them.
    private static func fragmentedSession(segmentCount: Int) -> [HeartRateDataPoint] {
        var samples: [HeartRateDataPoint] = []
        for segment in 0..<segmentCount {
            for second in 0..<Self.fragmentedSegmentLength {
                let elapsed = TimeInterval(segment * 72 + second)
                let heartRate: Int
                switch second {
                case 3: heartRate = 108 - segment % 7
                case 8: heartRate = 188 + segment % 7
                default: heartRate = 150
                }
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

    private static let fragmentedSegmentLength = 13

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

    /// The one a shrinking budget must never cost: a run that holds the session's
    /// peak keeps it however small its share of the marks, so the plotted extremes
    /// still match the raw ones and the axis headroom and the header's Max figure
    /// have something on the curve to point at.
    @Test
    func everyDropoutSegmentKeepsItsOwnPeakAndTrough() {
        let samples = Self.fragmentedSession(segmentCount: 200)
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 14_400
        )

        #expect(dataSet.segments.count == 200)

        let rawSegments = stride(from: 0, to: samples.count, by: Self.fragmentedSegmentLength).map { lowerBound in
            samples[lowerBound..<(lowerBound + Self.fragmentedSegmentLength)].map(\.heartRate)
        }
        let everySegmentKeepsItsExtremes = zip(rawSegments, dataSet.segments).allSatisfy { rawRates, segment in
            let plottedRates = segment.points.map(\.heartRate)
            guard let lowest = rawRates.min(), let highest = rawRates.max() else { return false }
            return plottedRates.contains(lowest) && plottedRates.contains(highest)
        }
        #expect(everySegmentKeepsItsExtremes)

        #expect(dataSet.points.map(\.heartRate).min() == samples.map(\.heartRate).min())
        #expect(dataSet.points.map(\.heartRate).max() == samples.map(\.heartRate).max())
    }

    /// The honest worst case of preferring extremes over the target: four marks per
    /// segment - endpoints plus the one bucket's low and high - so a pathological
    /// 200-dropout trace overshoots `maximumPlottedPointCount` while still plotting a
    /// small fraction of the raw series.
    @Test
    func aPathologicallyFragmentedTraceOvershootsTheTargetButStaysBounded() {
        let samples = Self.fragmentedSession(segmentCount: 200)
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 14_400
        )

        #expect(dataSet.points.count > HeartRateChartDataSet.maximumPlottedPointCount)
        #expect(dataSet.points.count <= dataSet.segments.count * 4)
        #expect(dataSet.points.count < samples.count / 3)
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

    /// The lookup is a binary search over the raw series; it has to agree with a
    /// scan of every sample, tie-breaking included, or the readout depends on how
    /// the search happened to land.
    @Test
    func theScrubLookupMatchesAScanOfTheWholeSeries() {
        let dataSet = HeartRateChartDataSet(
            samples: Self.longSession(),
            workoutStartTime: Self.start,
            workoutDuration: 2_603
        )
        let probes: [TimeInterval] = [
            -400, -0.4, 0, 0.4, 0.5, 0.6,
            1_234, 1_234.4, 1_234.5, 1_234.6,
            2_601.5, 2_602, 2_700
        ]

        let agrees = probes.allSatisfy { probe in
            dataSet.nearestScrubPoint(to: probe) == Self.nearestByScan(in: dataSet.scrubPoints, to: probe)
        }
        #expect(agrees)
    }

    /// Samples recorded just before the workout start clamp to the same elapsed
    /// value, so the lookup has to settle on the same one of them a scan would.
    @Test
    func theScrubLookupMatchesAScanWhenSamplesShareAnInstant() {
        let samples = [-30, -20, -10, 0, 5, 6, 7].map { offset in
            HeartRateDataPoint(
                timestamp: Self.start.addingTimeInterval(TimeInterval(offset)),
                heartRate: 140 + offset
            )
        }
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: 60
        )
        let probes: [TimeInterval] = [-10, 0, 1, 2, 2.5, 5, 6.5, 40, 120]

        let agrees = probes.allSatisfy { probe in
            dataSet.nearestScrubPoint(to: probe) == Self.nearestByScan(in: dataSet.scrubPoints, to: probe)
        }
        #expect(agrees)
    }

    private static func nearestByScan(
        in points: [HeartRateChartPoint],
        to elapsed: TimeInterval
    ) -> HeartRateChartPoint? {
        points.min { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) }
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
