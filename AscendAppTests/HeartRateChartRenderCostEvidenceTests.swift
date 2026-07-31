import Charts
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Renders the shipping heart-rate chart against the pre-fix mark set and writes the
/// proof to disk.
///
/// The plotted marks are the whole cost: before the fix the chart handed Swift Charts
/// one `LineMark` per raw sample, so this renders the same curve twice - once from the
/// raw series (`scrubPoints`, which is exactly what used to be plotted) and once from
/// the thinned series the view now plots - and compares both the wall-clock render
/// cost and the resulting pixels.
///
/// Images land in the test host's temporary directory; the paths are printed so a run
/// can lift them out for review.
@MainActor
struct HeartRateChartRenderCostEvidenceTests {
    private static let start = Date(timeIntervalSince1970: 1_750_300_000)
    private static let sessionSeconds = 2_603
    private static let chartSize = CGSize(width: 362, height: 200)
    private static let renderIterations = 5

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

        let beforeDuration = Self.medianRenderDuration(of: before)
        let afterDuration = Self.medianRenderDuration(of: after)

        let beforeImage = try #require(Self.render(before), "before image")
        let afterImage = try #require(Self.render(after), "after image")
        let difference = try Self.differingPixelFraction(beforeImage, afterImage)

        let overlay = try #require(
            Self.render(
                ZStack {
                    Color.black
                    Self.curve(segments: rawSegments, dataSet: dataSet, color: .white, lineWidth: 7)
                    Self.curve(segments: dataSet.segments, dataSet: dataSet, color: .red, lineWidth: 2)
                }
                .frame(width: Self.chartSize.width, height: Self.chartSize.height)
            ),
            "overlay image"
        )

        let full = try #require(
            Self.render(
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
                .environment(\.colorScheme, .dark)
            ),
            "full chart image"
        )

        let directory = try Self.evidenceDirectory()
        try Self.write(beforeImage, to: directory, named: "heart-rate-chart-before.png")
        try Self.write(afterImage, to: directory, named: "heart-rate-chart-after.png")
        try Self.write(overlay, to: directory, named: "heart-rate-chart-overlay.png")
        try Self.write(full, to: directory, named: "heart-rate-chart-full.png")

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
          images          \(directory.path())
        """
        print(report)
        try Data(report.utf8).write(to: directory.appending(path: "heart-rate-chart-render-cost.txt"))

        #expect(rawMarkCount == Self.sessionSeconds)
        #expect(thinnedMarkCount <= HeartRateChartDataSet.maximumPlottedPointCount)
        #expect(plottedRates.max() == rawRates.max())
        #expect(plottedRates.min() == rawRates.min())
        #expect(
            difference < 0.10,
            "the thinned curve should trace the raw one, but \(String(format: "%.2f", difference * 100))% of pixels differ"
        )
    }

    /// Screenshots the real activity detail screen for the session that stuttered, at
    /// the top and mid-scroll, so the fix can be reviewed as the screen a climber sees.
    @Test
    func theActivityDetailScreenRendersTheSessionThatStuttered() throws {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let workout = Self.stutteringWorkout()
        container.mainContext.insert(workout)

        let host = UIHostingController(
            rootView: WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        )

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.rootViewController = nil
            window.isHidden = true
        }
        Self.flush(window)

        let scrollView = try #require(Self.firstScrollView(in: window), "detail ScrollView")
        Self.flush(window)

        let directory = try Self.evidenceDirectory()
        Self.settle(window)
        try Self.write(Self.snapshot(window), to: directory, named: "activity-detail-top.png")

        // Just past the reveal threshold: the header takes the title over from the
        // inline row.
        scrollView.contentOffset = CGPoint(x: 0, y: WorkoutDetailView.navigationTitleRevealOffset + 40)
        Self.settle(window)
        try Self.write(Self.snapshot(window), to: directory, named: "activity-detail-title-revealed.png")

        // Far enough down that the heart-rate chart - the expensive section - clears
        // the header and sits fully on screen.
        scrollView.contentOffset = CGPoint(x: 0, y: 330)
        Self.settle(window)
        try Self.write(Self.snapshot(window), to: directory, named: "activity-detail-heart-rate.png")

        print("activity detail screenshots: \(directory.path())")
        #expect(scrollView.contentSize.height > 1_400)
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

    private static func render(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// Median rather than mean so a single scheduling hiccup on a loaded machine does
    /// not decide the number.
    private static func medianRenderDuration(of view: some View) -> Duration {
        _ = render(view) // warm the font and chart machinery
        let samples = (0..<renderIterations)
            .map { _ in ContinuousClock().measure { _ = render(view) } }
            .sorted()
        return samples[samples.count / 2]
    }

    private static func snapshot(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.1f", value)
    }

    // MARK: - Pixel comparison

    /// Share of pixels whose colour differs by more than an antialiasing wobble.
    private static func differingPixelFraction(_ lhs: UIImage, _ rhs: UIImage) throws -> Double {
        let left = try pixels(of: lhs)
        let right = try pixels(of: rhs)
        #expect(left.count == right.count, "images should share a size")

        var differing = 0
        for index in stride(from: 0, to: min(left.count, right.count), by: 4) {
            let delta = (0..<4).reduce(0) { running, channel in
                max(running, abs(Int(left[index + channel]) - Int(right[index + channel])))
            }
            if delta > 32 { differing += 1 }
        }
        return Double(differing) / Double(left.count / 4)
    }

    private static func pixels(of image: UIImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage, "image should be CG backed")
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            "bitmap context"
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    // MARK: - Files

    private static func evidenceDirectory() throws -> URL {
        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "heart-rate-chart-evidence")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ image: UIImage, to directory: URL, named name: String) throws {
        let png = try #require(image.pngData(), "\(name) should encode to PNG")
        try png.write(to: directory.appending(path: name))
    }

    // MARK: - Hosting helpers

    private static func flush(_ window: UIWindow) {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    /// A screenshot taken the instant after a scroll catches Swift Charts mid-draw, so
    /// let the render loop run itself out before capturing.
    private static func settle(_ window: UIWindow) {
        for _ in 0..<5 {
            flush(window)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
