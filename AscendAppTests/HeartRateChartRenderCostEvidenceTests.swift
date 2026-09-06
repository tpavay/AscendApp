import Charts
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Renders the shipping heart-rate chart against the pre-fix mark set and holds the thinning
/// invariants.
///
/// The plotted marks are the whole cost: before the fix the chart handed Swift Charts
/// one `LineMark` per raw sample, so this renders the same curve twice - once from the
/// raw series (`scrubPoints`, which is exactly what used to be plotted) and once from
/// the thinned series the view now plots - and compares both the wall-clock render
/// cost and the resulting pixels, read through `RenderedScreen.withOffscreenPixels`.
///
/// Photographs land in `ASCEND_EVIDENCE_DIR` when it is set and are not taken otherwise.
///
/// The render timings are printed for the record and never asserted - a wall-clock
/// threshold would flake on a loaded runner. Only the mark counts, the preserved
/// min/max envelope, and the pixel-difference bound are assertions.
@MainActor
@Suite(.hostsAWindow)
struct HeartRateChartRenderCostEvidenceTests {
    private static let start = Date(timeIntervalSince1970: 1_750_300_000)
    private static let sessionSeconds = 2_603
    private static let chartSize = CGSize(width: 362, height: 200)
    private static let renderIterations = 5
    /// The scale the timings and the pixel comparison were always taken at. A timing at a
    /// different scale is a different number, so this stays at 2 rather than the 1x a colour or
    /// position read would use.
    private static let renderScale: CGFloat = 2

    @Test
    func theThinnedChartDrawsTheSameCurveForAFractionOfTheRenderCost() throws {
        let samples = Self.session()
        let dataSet = HeartRateChartDataSet(
            samples: samples,
            workoutStartTime: Self.start,
            workoutDuration: TimeInterval(Self.sessionSeconds)
        )

        // What the view plotted before the fix: every raw sample, segmented the same way.
        let rawSegments = HeartRateChartDataSet.segments(for: dataSet.scrubPoints)
        let rawMarkCount = rawSegments.reduce(0) { $0 + $1.points.count }
        let thinnedMarkCount = dataSet.points.count

        let before = Self.curve(segments: rawSegments, dataSet: dataSet)
        let after = Self.curve(segments: dataSet.segments, dataSet: dataSet)

        let beforeDuration = try Self.medianRenderDuration(of: before)
        let afterDuration = try Self.medianRenderDuration(of: after)

        let difference = try Self.differingPixelFraction(before, after)

        try RenderedScreen.photograph(before, named: "heart-rate-chart-before", scale: Self.renderScale)
        try RenderedScreen.photograph(after, named: "heart-rate-chart-after", scale: Self.renderScale)
        try RenderedScreen.photograph(
            ZStack {
                Color.black
                Self.curve(segments: rawSegments, dataSet: dataSet, color: .white, lineWidth: 7)
                Self.curve(segments: dataSet.segments, dataSet: dataSet, color: .red, lineWidth: 2)
            }
            .frame(width: Self.chartSize.width, height: Self.chartSize.height),
            named: "heart-rate-chart-overlay",
            scale: Self.renderScale
        )
        try RenderedScreen.photograph(
            HeartRateChartView(
                heartRateData: samples,
                workoutStartTime: Self.start,
                workoutDuration: TimeInterval(Self.sessionSeconds),
                averageHeartRateBpm: 154,
                maxHeartRateBpm: samples.map(\.heartRate).max()
            )
            .padding(20)
            .frame(width: 402)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            named: "heart-rate-chart-full",
            scale: Self.renderScale
        )

        let rawRates = samples.map(\.heartRate)
        let plottedRates = dataSet.points.map(\.heartRate)
        let report = """
        heart-rate chart render cost, \(Self.sessionSeconds / 60)m\(Self.sessionSeconds % 60)s session at 1 Hz
          plotted marks   before \(rawMarkCount)   after \(thinnedMarkCount)
          render (median of \(Self.renderIterations))   before \(Self.milliseconds(beforeDuration)) ms   after \(Self.milliseconds(afterDuration)) ms
          differing pixels  \(String(format: "%.2f", difference * 100))%
          peak BPM        raw \(rawRates.max() ?? 0)   plotted \(plottedRates.max() ?? 0)
          trough BPM      raw \(rawRates.min() ?? 0)   plotted \(plottedRates.min() ?? 0)
          axis range      \(dataSet.heartRateRange.lowerBound)...\(dataSet.heartRateRange.upperBound)
          images          \(RenderedScreen.evidenceDirectory?.path() ?? "not written - ASCEND_EVIDENCE_DIR is unset")
        """
        print(report)
        if let directory = RenderedScreen.evidenceDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(report.utf8).write(to: directory.appending(path: "heart-rate-chart-render-cost.txt"))
        }

        #expect(rawMarkCount == Self.sessionSeconds)
        #expect(thinnedMarkCount <= HeartRateChartDataSet.maximumPlottedPointCount)
        #expect(plottedRates.max() == rawRates.max())
        #expect(plottedRates.min() == rawRates.min())
        #expect(
            difference < 0.10,
            "the thinned curve should trace the raw one, but \(String(format: "%.2f", difference * 100))% of pixels differ"
        )
    }

    /// Hosts the real activity detail screen for the session that stuttered and photographs it
    /// at the top and mid-scroll when `ASCEND_EVIDENCE_DIR` is set, so the fix can be reviewed as
    /// the screen a climber sees.
    @Test
    func theActivityDetailScreenRendersTheSessionThatStuttered() async throws {
        let container = try Self.hostedContainer()

        let workout = Self.stutteringWorkout()
        container.mainContext.insert(workout)

        let host = UIHostingController(
            rootView: WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        )

        // `RenderedScreen` detaches the window from the scene on the way out, which is what
        // dismantles the content. Hiding would not be enough: a window still attached keeps
        // `WorkoutDetailView`'s `@Query` observing SwiftData after the container declared above
        // has gone, and that observer then traps on the next save any other suite performs,
        // taking the whole test process down.
        try await RenderedScreen.host(host) { screen in
            let scrollView = try #require(Self.firstScrollView(in: screen.window), "detail ScrollView")
            try screen.photograph(named: "activity-detail-top")

            // Just past the reveal threshold: the header takes the title over from the
            // inline row.
            scrollView.contentOffset = CGPoint(x: 0, y: WorkoutDetailView.navigationTitleRevealOffset + 40)
            // A photograph taken the instant after a scroll catches Swift Charts mid-draw, so
            // let the render loop run itself out before capturing.
            try await screen.settle(.turns(5))
            try screen.photograph(named: "activity-detail-title-revealed")

            // Far enough down that the heart-rate chart - the expensive section - clears
            // the header and sits fully on screen.
            scrollView.contentOffset = CGPoint(x: 0, y: 330)
            try await screen.settle(.turns(5))
            try screen.photograph(named: "activity-detail-heart-rate")

            #expect(scrollView.contentSize.height > 1_400)
        }
    }

    // MARK: - Fixtures

    /// Hard ramp, plateau, a dip, then interval spikes - the shape of the recording.
    private static func session() -> [HeartRateDataPoint] {
        var rate = 62.0
        return (0..<sessionSeconds).map { second in
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

    /// Held for the process, not built per test.
    ///
    /// `WorkoutDetailView` carries a `@Query`, and SwiftUI keeps observing SwiftData for a beat
    /// after the host is torn down. A container that dies with the test is gone before that
    /// observer is, and the observer then traps on the dangling reference the next time *any*
    /// suite calls `ModelContext.save()` - taking the whole test process down with it, attributed
    /// to whatever unrelated code happened to be saving.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private static func hostedContainer() throws -> ModelContainer {
        try #require(container, "The evidence suite needs an in-memory model container")
    }

    private static func stutteringWorkout() -> Workout {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: sessionSeconds * 50,
            trackingMode: .routine,
            climbId: nil,
            targetStepCount: 4_134,
            stopReason: .userStopped,
            splitCurve: LiveReplaySplitCurve(
                intervalSeconds: 300,
                steps: [370, 876, 1_383, 1_840, 2_375, 2_835, 3_361, 3_895, 4_134]
            )
        )
        let samples = session()

        return Workout(
            name: "Threshold Intervals",
            date: start,
            duration: TimeInterval(sessionSeconds),
            steps: 4_134,
            floors: 258,
            avgHeartRate: 154,
            maxHeartRate: samples.map(\.heartRate).max() ?? 177,
            caloriesBurned: 669,
            heartRateTimeSeries: samples,
            averageMETs: 11.4,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    // MARK: - Rendering

    private static func curve(
        segments: [HeartRateChartSegment],
        dataSet: HeartRateChartDataSet,
        color: Color = .red,
        lineWidth: CGFloat = 3
    ) -> some View {
        Chart {
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Time", point.elapsed),
                        y: .value("Heart Rate", point.heartRate),
                        series: .value("Segment", segment.id)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .chartXScale(domain: 0...dataSet.duration)
        .chartYScale(domain: dataSet.heartRateRange)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: chartSize.width, height: chartSize.height)
    }

    /// One timed render at `renderScale`, through the same off-screen path the pixel comparison
    /// reads. The bitmap is released before this returns; what is measured includes the sampler's
    /// readback, the same on both sides of the comparison.
    private static func render(_ view: some View) throws {
        try RenderedScreen.withOffscreenPixels(of: view, scale: renderScale) { _ in }
    }

    /// Median rather than mean so a single scheduling hiccup on a loaded machine does
    /// not decide the number.
    private static func medianRenderDuration(of view: some View) throws -> Duration {
        try render(view) // warm the font and chart machinery
        var samples: [Duration] = []
        for _ in 0..<renderIterations {
            samples.append(try ContinuousClock().measure { try render(view) })
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.1f", value)
    }

    // MARK: - Pixel comparison

    /// Share of pixels whose colour differs by more than an antialiasing wobble. Each side's
    /// pixels are lifted out of their own off-screen render so no two bitmaps are ever held at
    /// once.
    private static func differingPixelFraction(_ lhs: some View, _ rhs: some View) throws -> Double {
        let left = try pixels(of: lhs)
        let right = try pixels(of: rhs)
        #expect(left.count == right.count, "images should share a size")

        var differing = 0
        for index in 0..<min(left.count, right.count) {
            let delta = max(
                abs(Int(left[index].red) - Int(right[index].red)),
                abs(Int(left[index].green) - Int(right[index].green)),
                abs(Int(left[index].blue) - Int(right[index].blue)),
                abs(Int(left[index].alpha) - Int(right[index].alpha))
            )
            if delta > 32 { differing += 1 }
        }
        return Double(differing) / Double(left.count)
    }

    private static func pixels(of view: some View) throws -> [RGBA] {
        try RenderedScreen.withOffscreenPixels(of: view, scale: renderScale) { pixels in
            pixels.pixels(in: CGRect(origin: .zero, size: pixels.size))
        }
    }

    // MARK: - Hosting helpers

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
