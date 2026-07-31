//
//  HeartRateChartView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI
import Charts

struct HeartRateChartDataSet: Equatable {
    static let minimumLineSampleCount = 3
    /// A gap this many times wider than the series' own median spacing is a
    /// dropout rather than cadence jitter. Scaling off the series keeps sparse
    /// imported samples (minutes apart by nature) rendering as one trace while
    /// still breaking ~1 Hz live capture where the strap actually went silent.
    static let dropoutGapMultiplier: Double = 4
    /// Floor so a couple of skipped 1 Hz notifications never shatter the line.
    static let minimumDropoutGap: TimeInterval = 10

    /// Target for the plotted mark count. A 43-minute session records one sample per
    /// second, and handing Swift Charts 2,600 `LineMark`s costs ~114 ms to render
    /// - seven 60 Hz frames for detail no chart this size can show. Capping the
    /// mark count keeps the same curve at roughly an eighth of the cost.
    ///
    /// It holds exactly for a continuous trace and for the handful of dropouts a real
    /// session sees. It is a target rather than a hard bound because every segment,
    /// however small its share, still contributes its own minimum and maximum on top
    /// of its endpoints - up to four marks - so that a run containing the session's
    /// peak can never lose it to fragmentation. A pathological trace of ~200 dropouts
    /// therefore plots roughly `4 x segment count` marks, over this target. Accuracy
    /// wins that trade: a chart missing the peak is a worse bug than a slow one.
    static let maximumPlottedPointCount = 400

    let points: [HeartRateChartPoint]
    /// The full unthinned series, kept for the scrub readout only. Thinning is a
    /// rendering concession; the "### BPM at m:ss" a climber reads off the chart
    /// has to be the actual sample under their finger, not a nearby bucket extreme.
    let scrubPoints: [HeartRateChartPoint]
    let segments: [HeartRateChartSegment]
    let duration: TimeInterval
    let heartRateRange: ClosedRange<Int>
    let heartRateTickValues: [Int]

    var canPlotLine: Bool {
        let distinctElapsedValues = Set(points.map { Int($0.elapsed.rounded()) })
        return points.count >= Self.minimumLineSampleCount && distinctElapsedValues.count >= 2
    }

    /// The reading under a scrub touch, resolved against the full series rather than
    /// the plotted subset so the BPM and the "at m:ss" label are the real sample.
    ///
    /// `scrubPoints` is non-decreasing in `elapsed` by construction, so the touch
    /// lands between two neighbours rather than needing a scan of all 2,600 samples
    /// - a scrub drag re-evaluates the body on every touch move.
    func nearestScrubPoint(to elapsed: TimeInterval) -> HeartRateChartPoint? {
        guard !scrubPoints.isEmpty else { return nil }

        let insertionIndex = firstIndex(atOrAfter: elapsed)
        guard insertionIndex > 0 else { return scrubPoints[0] }
        guard insertionIndex < scrubPoints.count else { return scrubPoints[lastTiedIndex(before: insertionIndex)] }

        let earlier = scrubPoints[lastTiedIndex(before: insertionIndex)]
        let later = scrubPoints[insertionIndex]
        return abs(later.elapsed - elapsed) < abs(earlier.elapsed - elapsed) ? later : earlier
    }

    /// Index of the first point at or after `elapsed`, or `count` when every point
    /// precedes it.
    private func firstIndex(atOrAfter elapsed: TimeInterval) -> Int {
        var low = 0
        var high = scrubPoints.count
        while low < high {
            let middle = low + (high - low) / 2
            if scrubPoints[middle].elapsed < elapsed {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// Samples clamped to the same instant are interchangeable by distance, and the
    /// earliest of them is the one a scan of the series would settle on.
    private func lastTiedIndex(before insertionIndex: Int) -> Int {
        firstIndex(atOrAfter: scrubPoints[insertionIndex - 1].elapsed)
    }

    init(
        samples: [HeartRateDataPoint],
        workoutStartTime: Date,
        workoutDuration: TimeInterval
    ) {
        let visibleDuration = max(workoutDuration, 1)
        let workoutEndTime = workoutStartTime.addingTimeInterval(visibleDuration)
        let tolerance: TimeInterval = 60
        let sortedSamples = samples
            .filter { sample in
                sample.heartRate > 0 &&
                    sample.timestamp >= workoutStartTime.addingTimeInterval(-tolerance) &&
                    sample.timestamp <= workoutEndTime.addingTimeInterval(tolerance)
            }
            .sorted { $0.timestamp < $1.timestamp }

        let rawPoints = sortedSamples.enumerated().map { index, sample in
            HeartRateChartPoint(
                id: index,
                elapsed: min(max(sample.timestamp.timeIntervalSince(workoutStartTime), 0), visibleDuration),
                heartRate: sample.heartRate
            )
        }

        // Dropout detection runs on the raw series and thinning happens inside each
        // resulting segment. Doing it the other way round would let thinning rewrite
        // the sample spacing the gap threshold is derived from, inventing dropouts in
        // a continuous trace or papering over real ones.
        segments = Self.thinnedSegments(Self.segments(for: rawPoints), rawPointCount: rawPoints.count)
        points = segments.flatMap(\.points)
        scrubPoints = rawPoints
        duration = visibleDuration

        // Ranged off the full series, not the plotted subset, so the axis still
        // spans the real minimum and maximum even when marks are thinned.
        heartRateRange = Self.range(for: sortedSamples.map(\.heartRate))
        heartRateTickValues = Self.tickValues(for: heartRateRange)
    }

    /// Thins each segment to a share of the mark budget proportional to its length.
    ///
    /// A 43-minute session records one sample per second, and handing Swift Charts
    /// 2,600 `LineMark`s costs ~114 ms to render - seven 60 Hz frames for detail no
    /// chart this size can show.
    ///
    /// Every segment first reserves its own endpoints so a short run is never thinned
    /// out of existence; what is left of the target is then shared out in proportion
    /// to segment length. A segment never drops below one bucket, so a heavily
    /// fragmented trace can plot up to four marks per segment and overshoot
    /// `maximumPlottedPointCount` - see that constant for why accuracy wins there.
    private static func thinnedSegments(
        _ segments: [HeartRateChartSegment],
        rawPointCount: Int
    ) -> [HeartRateChartSegment] {
        guard rawPointCount > maximumPlottedPointCount else {
            return segments
        }

        let reserved = segments.reduce(0) { $0 + min($1.points.count, 2) }
        let discretionary = max(maximumPlottedPointCount - reserved, 0)

        return segments.map { segment in
            let share = Double(segment.points.count) / Double(rawPointCount)
            let budget = min(segment.points.count, 2) + Int(Double(discretionary) * share)
            return HeartRateChartSegment(id: segment.id, points: thinned(segment.points, budget: budget))
        }
    }

    /// Keeps each bucket's lowest and highest reading in time order, plus the run's
    /// own endpoints. Dropping every Nth sample instead would clip the peaks and
    /// troughs - the part of a heart-rate trace a climber actually reads.
    ///
    /// The bucket count never falls below one, so even a segment allotted the bare
    /// minimum still contributes its own extremes rather than a straight chord
    /// between its endpoints.
    private static func thinned(_ points: [HeartRateChartPoint], budget: Int) -> [HeartRateChartPoint] {
        guard points.count > budget else { return points }

        // Two marks come out of each bucket, and the two endpoints are added back
        // afterwards, so the bucket budget has to leave room for both.
        let bucketCount = max((budget - 2) / 2, 1)

        var kept: [HeartRateChartPoint] = []
        kept.reserveCapacity(budget)

        for bucket in 0..<bucketCount {
            let lowerBound = points.count * bucket / bucketCount
            let upperBound = points.count * (bucket + 1) / bucketCount
            guard lowerBound < upperBound else { continue }

            let slice = points[lowerBound..<upperBound]
            guard let lowest = slice.min(by: { $0.heartRate < $1.heartRate }),
                  let highest = slice.max(by: { $0.heartRate < $1.heartRate }) else {
                continue
            }

            if lowest.id == highest.id {
                kept.append(lowest)
            } else if lowest.id < highest.id {
                kept.append(contentsOf: [lowest, highest])
            } else {
                kept.append(contentsOf: [highest, lowest])
            }
        }

        if let first = points.first, kept.first?.id != first.id {
            kept.insert(first, at: 0)
        }
        if let last = points.last, kept.last?.id != last.id {
            kept.append(last)
        }

        return kept
    }

    /// Splits the trace wherever coverage actually stopped, so a dropout reads
    /// as missing data instead of an interpolated straight line.
    static func segments(for points: [HeartRateChartPoint]) -> [HeartRateChartSegment] {
        guard points.count > 1 else {
            return points.isEmpty ? [] : [HeartRateChartSegment(id: 0, points: points)]
        }

        let spacings = zip(points, points.dropFirst()).map { $1.elapsed - $0.elapsed }
        let threshold = max(median(of: spacings) * dropoutGapMultiplier, minimumDropoutGap)

        var segments: [HeartRateChartSegment] = []
        var current: [HeartRateChartPoint] = [points[0]]
        for (previous, point) in zip(points, points.dropFirst()) {
            if point.elapsed - previous.elapsed > threshold {
                segments.append(HeartRateChartSegment(id: segments.count, points: current))
                current = [point]
            } else {
                current.append(point)
            }
        }
        segments.append(HeartRateChartSegment(id: segments.count, points: current))
        return segments
    }

    private static func median(of values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func range(for heartRates: [Int]) -> ClosedRange<Int> {
        guard let minRate = heartRates.min(), let maxRate = heartRates.max() else {
            return 60...180
        }

        if minRate == maxRate {
            return max(30, minRate - 5)...(maxRate + 5)
        }

        let padding = max(3, Int(ceil(Double(maxRate - minRate) * 0.1)))
        return max(30, minRate - padding)...(maxRate + padding)
    }

    private static func tickValues(for range: ClosedRange<Int>) -> [Int] {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return [range.lowerBound] }

        let interval = Double(distance) / 4.0
        var ticks = (0...4).map { index in
            range.lowerBound + Int(round(Double(index) * interval))
        }
        ticks[0] = range.lowerBound
        ticks[4] = range.upperBound
        return ticks
    }
}

struct HeartRateChartPoint: Identifiable, Equatable {
    let id: Int
    let elapsed: TimeInterval
    let heartRate: Int
}

/// One run of contiguously sampled points. Separate segments are drawn as
/// separate lines so the space between them stays visibly empty.
struct HeartRateChartSegment: Identifiable, Equatable {
    let id: Int
    let points: [HeartRateChartPoint]
}

struct HeartRateChartView: View {
    let heartRateData: [HeartRateDataPoint]
    let workoutStartTime: Date
    let workoutDuration: TimeInterval
    let averageHeartRateBpm: Int?
    let maxHeartRateBpm: Int?

    /// Built once per view value rather than on demand. The body reads it eight
    /// times (marks, both scales, both axes, selection), and scrubbing the chart
    /// re-evaluates the body on every touch move - as a computed property that
    /// meant re-filtering and re-sorting the whole series each time.
    private let dataSet: HeartRateChartDataSet

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var rawSelectedTime: TimeInterval?
    @State private var stickySelectedTime: TimeInterval?

    init(
        heartRateData: [HeartRateDataPoint],
        workoutStartTime: Date,
        workoutDuration: TimeInterval,
        averageHeartRateBpm: Int?,
        maxHeartRateBpm: Int?
    ) {
        self.heartRateData = heartRateData
        self.workoutStartTime = workoutStartTime
        self.workoutDuration = workoutDuration
        self.averageHeartRateBpm = averageHeartRateBpm
        self.maxHeartRateBpm = maxHeartRateBpm
        self.dataSet = HeartRateChartDataSet(
            samples: heartRateData,
            workoutStartTime: workoutStartTime,
            workoutDuration: workoutDuration
        )
    }


    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var computedSelectedPoint: HeartRateChartPoint? {
        guard let activeTime = rawSelectedTime ?? stickySelectedTime else { return nil }

        return dataSet.nearestScrubPoint(to: activeTime)
    }

    private var averageHeartRate: Int? {
        if let averageHeartRateBpm {
            return averageHeartRateBpm
        }
        guard !heartRateData.isEmpty else { return nil }
        return heartRateData.map(\.heartRate).reduce(0, +) / heartRateData.count
    }

    private var maxHeartRate: Int? {
        maxHeartRateBpm ?? heartRateData.map(\.heartRate).max()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            headerView
            
            if dataSet.canPlotLine {
                chartView
            } else {
                unavailableChartView
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 6) {
            // Top row: "Heart Rate" title + always-visible avg/max
            HStack {
                Text("Heart Rate")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()

                HStack(spacing: 16) {
                    if let averageHeartRate {
                        HStack(spacing: 4) {
                            Text("Avg")
                                .font(.montserratRegular(size: 12))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text("\(averageHeartRate)")
                                .font(.montserratBold(size: 14))
                                .foregroundStyle(.red)
                        }
                    }
                    if let maxHeartRate {
                        HStack(spacing: 4) {
                            Text("Max")
                                .font(.montserratRegular(size: 12))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                            Text("\(maxHeartRate)")
                                .font(.montserratBold(size: 14))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // Selected point row (appears when user taps the graph)
            if let selected = computedSelectedPoint {
                HStack {
                    Spacer()
                    Text("\(selected.heartRate) BPM")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.red)
                    Text("at \(formatDuration(selected.elapsed))")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: computedSelectedPoint != nil)
    }
    
    private var unavailableChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray)
            
            Text(heartRateData.isEmpty ? "No heart-rate samples available" : "Not enough heart-rate samples to chart")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private var chartView: some View {
        Chart {
            ForEach(dataSet.segments) { segment in
                ForEach(segment.points) { data in
                    heartRateLineMark(data: data, series: segment.id)
                }

                if segment.points.count == 1, let isolated = segment.points.first {
                    isolatedSampleMark(data: isolated)
                }
            }

            if let selected = computedSelectedPoint {
                selectedPointMarks(elapsed: selected.elapsed, heartRate: selected.heartRate)
            }
        }
        .frame(height: 200)
        .chartXScale(domain: 0...dataSet.duration)
        .chartYScale(domain: dataSet.heartRateRange)
        .padding(16)
        .chartXAxis { xAxisMarks }
        .chartYAxis { yAxisMarks }
        .chartXSelection(value: $rawSelectedTime)
        .animation(.easeInOut(duration: 0.2), value: rawSelectedTime)
        .onChange(of: computedSelectedPoint) { oldValue, newValue in
            // Trigger haptic feedback when selection changes to a new heart rate value
            if let oldHR = oldValue?.heartRate, 
               let newHR = newValue?.heartRate,
               oldHR != newHR {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            } else if oldValue == nil && newValue != nil {
                // Initial selection
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        .onChange(of: rawSelectedTime) { _, newValue in
            if let newValue {
                stickySelectedTime = newValue
            }
        }
        .chartBackground { _ in
            backgroundView
        }
    }
    
    private func heartRateLineMark(data: HeartRateChartPoint, series: Int) -> some ChartContent {
        LineMark(
            x: .value("Time", data.elapsed),
            y: .value("Heart Rate", data.heartRate),
            series: .value("Segment", series)
        )
        .foregroundStyle(.red)
        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    private func isolatedSampleMark(data: HeartRateChartPoint) -> some ChartContent {
        PointMark(
            x: .value("Time", data.elapsed),
            y: .value("Heart Rate", data.heartRate)
        )
        .foregroundStyle(.red)
        .symbolSize(24)
    }
    
    @ChartContentBuilder
    private func selectedPointMarks(elapsed: TimeInterval, heartRate: Int) -> some ChartContent {
        PointMark(
            x: .value("Time", elapsed),
            y: .value("Heart Rate", heartRate)
        )
        .foregroundStyle(.red)
        .symbolSize(64)
        
        RuleMark(x: .value("Time", elapsed))
            .foregroundStyle(.red.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1))
    }
    
    private var xAxisMarks: some AxisContent {
        AxisMarks(values: [0, dataSet.duration / 4, dataSet.duration / 2, 3 * dataSet.duration / 4, dataSet.duration]) { value in
            if let elapsed = value.as(Double.self) {
                let anchor: UnitPoint = elapsed == dataSet.duration ? .topTrailing : (elapsed == 0 ? .topLeading : .top)
                AxisValueLabel(anchor: anchor) {
                    Text(formatDuration(elapsed))
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
                AxisTick()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
            }
        }
    }

    private var yAxisMarks: some AxisContent {
        AxisMarks(position: .leading, values: dataSet.heartRateTickValues) { value in
            if let heartRate = value.as(Int.self) {
                AxisValueLabel {
                    Text("\(heartRate)")
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
                AxisTick()
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.25))
            }
        }
    }
    
    private var backgroundView: some View {
        Rectangle()
            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

#Preview {
    let startTime = Date()
    let sampleData = [
        HeartRateDataPoint(timestamp: startTime, heartRate: 70),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(300), heartRate: 120),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(600), heartRate: 145),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(900), heartRate: 200),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1200), heartRate: 140),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1500), heartRate: 125),
        HeartRateDataPoint(timestamp: startTime.addingTimeInterval(1800), heartRate: 105)
    ]
    
    HeartRateChartView(
        heartRateData: sampleData,
        workoutStartTime: startTime,
        workoutDuration: 1800,
        averageHeartRateBpm: 129,
        maxHeartRateBpm: 200
    )
    .padding()
}
