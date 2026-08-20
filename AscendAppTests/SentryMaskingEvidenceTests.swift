import AVFoundation
import AVKit
import Foundation
import SwiftUI
import Testing
import UIKit
@_spi(Private) @preconcurrency import Sentry
@testable import AscendApp

/// Proves that what Sentry masks, it masks completely.
///
/// Ascend carries health data - heart rate, calories, session measurements -
/// alongside account identity and the climber's own photos and video, and
/// attaching a screenshot to a crash puts a rendering of their screen on the
/// wire. The SDK's masking defaults are a claim, not evidence, so
/// this suite runs Ascend's real surfaces through the SDK's own masking
/// pipeline - `SentryViewPhotographer` over the very options
/// `SentryOptionsFactory` hands the SDK - and asserts the property that matters.
///
/// The trick each case uses is to render the same surface twice with sensitive
/// content that is a **permutation** of itself: a reversed name, the same digits
/// in a different order, a mirrored photograph, a heart-rate trace played
/// backwards, a fixture movie against its own mirror. Monospaced type and
/// identical image dimensions keep the layout pixel-for-pixel identical, and a
/// permutation has the same average colour -
/// which matters because the SDK fills a masked region with the average of what
/// it covered rather than a fixed black
/// (`SentryDefaultMaskRenderer.applyMasking`).
///
/// So if masking is complete, the two masked renders are the same image: the
/// output can depend on *how much* ink was under the mask but not on how it was
/// arranged. A digit, a glyph, a face or a chart line that survived would put
/// dark pixels where the other variant has light ones. Each case carries a
/// control asserting the unmasked renders differ enormously, so a passing
/// comparison can never be two blank canvases.
///
/// What masking does **not** hide, and no configuration can: the size and
/// position of the masked rectangle. A masked region is the covered view's own
/// frame, so a screenshot still shows that a label is wide, not what it says.
///
/// Both renders of every case are written out for the record - the unmasked
/// control beside the masked result, so the pair reads as before-and-after; set
/// `ASCEND_EVIDENCE_DIR` to collect them somewhere durable.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct SentryMaskingEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 500)
    private static let chartStart = Date(timeIntervalSince1970: 1_750_300_000)
    private static let chartDuration: TimeInterval = 1_800

    // MARK: - Health

    @Test
    func aHeartRateChartRendersIdenticallyWhateverTheClimbersHeartDid() async throws {
        // The same 600 readings, played forwards and backwards: identical range,
        // so identical axis ticks, and identical average and maximum, so an
        // identical header. Only the trace moves.
        let series = (0..<600).map { second in 100 + Int((sin(Double(second) / 37) * 40).rounded()) }

        try await Self.expectSensitiveContentMasked(
            Self.chart(readings: series),
            Self.chart(readings: series.reversed()),
            named: "heart-rate-chart"
        )
    }

    @Test
    func healthReadoutsRenderIdenticallyWhateverTheyMeasured() async throws {
        try await Self.expectSensitiveContentMasked(
            Self.readout(bpm: "188", calories: "947", weight: "264"),
            Self.readout(bpm: "881", calories: "749", weight: "462"),
            named: "health-readout"
        )
    }

    @Test
    func userMediaRendersIdenticallyWhateverItShows() async throws {
        let photo = Self.photograph()

        try await Self.expectSensitiveContentMasked(
            Self.media(photo),
            Self.media(photo.mirrored()),
            named: "user-media"
        )
    }

    // MARK: - Climb footage

    // A view that hosts its own `AVPlayerLayer` is the one category the SDK
    // covers with nothing of its own.
    //
    // `maskAllImages` covers `UIImageView`; an `AVPlayerLayer` draws straight
    // into its host view and is neither text nor an image as far as the SDK is
    // concerned. Without `sentryMasked()` a climber's own footage reaches a
    // crash screenshot at full fidelity, and the privacy policy promises the
    // opposite - so these three cases are that promise's evidence, one per
    // surface that plays video.
    //
    // Every frame of the fixture movie is the same picture, which is what makes
    // the comparison sound: two of the three surfaces start playing on their
    // own, so the two renders cannot be pinned to the same playback position,
    // and a movie that looks the same at every instant removes the question.
    // The permutation is the mirror of that picture.
    //
    // **These three do not have equal force, and the difference matters.** Emptying
    // `maskedViewClasses` fails the workout card and the share composer with a
    // worst channel of 255 - their footage really is on the wire without
    // Ascend's marker. The full-screen player still passes, because
    // `SentryUIRedactBuilder` redacts `AVPlayerView` by default and
    // `AVPlayerViewController` renders through one. So that case is evidence
    // the footage is masked, not evidence that Ascend's mask is what masks it.
    // Do not read a green full-screen case as cover for deleting the marker
    // there - it would leave the surface resting entirely on a default list the
    // SDK is free to change.

    @Test
    func workoutCardFootageRendersIdenticallyWhateverItShows() async throws {
        let footage = try await Self.footage()
        defer { footage.discard() }

        try await Self.expectSensitiveContentMasked(
            VideoPlayerView(player: AVPlayer(url: footage.original)).frame(height: 320),
            VideoPlayerView(player: AVPlayer(url: footage.mirrored)).frame(height: 320),
            named: "workout-card-footage",
            settledWhen: Self.playerIsShowingItsFootage
        )
    }

    @Test
    func theShareComposerBackgroundRendersIdenticallyWhateverItShows() async throws {
        let footage = try await Self.footage()
        defer { footage.discard() }

        try await Self.expectSensitiveContentMasked(
            ShareBackgroundView(source: .video(footage.original)),
            ShareBackgroundView(source: .video(footage.mirrored)),
            named: "share-composer-background",
            settledWhen: Self.playerIsShowingItsFootage
        )
    }

    /// The full-screen player is `AVPlayerViewController`, whose transport
    /// controls sit above the footage. They carry no climber content and render
    /// identically in both variants, so they cost the comparison nothing.
    @Test
    func theFullScreenPlayerRendersIdenticallyWhateverItShows() async throws {
        let footage = try await Self.footage()
        defer { footage.discard() }

        try await Self.expectSensitiveContentMasked(
            FullScreenPhotoView(photo: Self.video(footage.original), onDismiss: {}),
            FullScreenPhotoView(photo: Self.video(footage.mirrored), onDismiss: {}),
            named: "full-screen-player",
            settledWhen: Self.playerIsShowingItsFootage
        )
    }

    // MARK: - The other charts

    // Swift Charts draws its marks into a `CALayer` the SDK reads as neither
    // text nor an image, so every chart that plots the climber's own numbers
    // needs the marker - and every one of them needs the evidence, because a
    // mask that was never applied looks exactly like a mask that works until
    // something renders through it.

    @Test
    func theProgressChartRendersIdenticallyWhateverItPlots() async throws {
        let values = (0..<12).map { Double(2_000 + $0 * 130) }

        try await Self.expectSensitiveContentMasked(
            Self.progressChart(values: values),
            Self.progressChart(values: values.reversed()),
            named: "progress-line-chart"
        )
    }

    @Test
    func theWeeklyStepsChartRendersIdenticallyWhateverItPlots() async throws {
        // The most recent week is held fixed in both variants: it is the one the
        // chart reads out in its header, and a different number there would move
        // the text's masked rectangle rather than what is inside it.
        let steps = (1...8).map { 2_400 + $0 * 310 }

        try await Self.expectSensitiveContentMasked(
            Self.weeklyStepsChart(earlierWeeks: steps),
            Self.weeklyStepsChart(earlierWeeks: steps.reversed()),
            named: "weekly-steps-chart"
        )
    }

    @Test
    func theTrendChartRendersIdenticallyWhateverItPlots() async throws {
        let values = (0..<24).map { Double(90 + ($0 * 7) % 40) }

        try await Self.expectSensitiveContentMasked(
            Self.trendChart(values: values),
            Self.trendChart(values: values.reversed()),
            named: "trend-chart"
        )
    }

    // MARK: - Identity

    @Test
    func aClimbersIdentityRendersIdenticallyWhoeverTheyAre() async throws {
        let displayName = "Alexandra Featherst"
        let handle = "alexandra@example.com"
        let accountID = "cW1nZXVzZXItMDAwMDAwMDE"

        try await Self.expectSensitiveContentMasked(
            Self.identity(displayName: displayName, handle: handle, accountID: accountID),
            Self.identity(
                displayName: String(displayName.reversed()),
                handle: String(handle.reversed()),
                accountID: String(accountID.reversed())
            ),
            named: "identity"
        )
    }

    // MARK: - Comparison

    /// The most a single colour channel may differ between the two masked
    /// renders. Antialiasing means a permutation is not a pixel-exact
    /// rearrangement, so the averaged fill can land a step apart; nothing
    /// legible survives inside a margin this narrow.
    private static let maskedTolerance = 2

    /// How far apart the *unmasked* renders must be for the case to mean
    /// anything - a legible difference, not a rounding one.
    private static let controlThreshold = 64

    /// Renders both views twice - once raw, once through the SDK's masking - and
    /// asserts the masked pair is the same image while the raw pair is not.
    private static func expectSensitiveContentMasked(
        _ first: some View,
        _ second: some View,
        named name: String,
        settledWhen isSettled: @escaping @MainActor (UIView) -> Bool = { _ in true }
    ) async throws {
        let rawDifference = try await difference(
            render(first, masked: false, savedAs: "\(name)-unmasked-a", settledWhen: isSettled),
            render(second, masked: false, savedAs: "\(name)-unmasked-b", settledWhen: isSettled)
        )
        let maskedDifference = try await difference(
            render(first, masked: true, savedAs: "\(name)-masked-a", settledWhen: isSettled),
            render(second, masked: true, savedAs: "\(name)-masked-b", settledWhen: isSettled)
        )

        // Control: the two renders really do differ before masking, so an
        // identical masked pair is masking rather than an empty canvas.
        #expect(
            rawDifference.maximumChannelDelta >= controlThreshold,
            """
            \(name): the unmasked renders differ by at most \(rawDifference.maximumChannelDelta), \
            below the \(controlThreshold) this case needs to prove anything.
            """
        )

        #expect(
            maskedDifference.maximumChannelDelta <= maskedTolerance,
            """
            \(name): \(maskedDifference.pixelsBeyondTolerance) pixels of the masked render depend on \
            how the sensitive content was arranged (worst channel off by \
            \(maskedDifference.maximumChannelDelta)), so this surface can reach a Sentry crash \
            screenshot legibly. Masked renders were written to \(evidenceDirectory.path()).
            """
        )
    }

    private struct Difference {
        let maximumChannelDelta: Int
        let pixelsBeyondTolerance: Int
    }

    private static func difference(_ first: Bitmap, _ second: Bitmap) -> Difference {
        guard first.width == second.width, first.height == second.height else {
            return Difference(maximumChannelDelta: 255, pixelsBeyondTolerance: first.width * first.height)
        }

        var maximumDelta = 0
        var beyondTolerance = 0

        for y in 0..<first.height {
            for x in 0..<first.width {
                let delta = first.channelDelta(to: second, x: x, y: y)
                maximumDelta = max(maximumDelta, delta)
                if delta > maskedTolerance { beyondTolerance += 1 }
            }
        }

        return Difference(maximumChannelDelta: maximumDelta, pixelsBeyondTolerance: beyondTolerance)
    }

    // MARK: - Rendering

    /// Hosts `view` in the shared window scene and reads it back, optionally
    /// through the exact masking pipeline the SDK uses for crash screenshots.
    private static func render(
        _ view: some View,
        masked: Bool,
        savedAs name: String? = nil,
        settledWhen isSettled: @MainActor (UIView) -> Bool = { _ in true }
    ) async throws -> Bitmap {
        let controller = UIHostingController(
            rootView: view
                .frame(width: screenSize.width, height: screenSize.height)
                .transaction { $0.disablesAnimations = true }
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: screenSize)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: screenSize))
        window.frame = CGRect(origin: .zero, size: screenSize)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // A turn of the run loop so SwiftUI has committed its hosting views and
        // layers before the hierarchy is walked for redaction regions.
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
        try await settle(controller.view, isSettled)

        let image: UIImage
        if masked {
            // The very options the app hands the SDK, and the same renderer
            // selection the SDK makes from them.
            let options = SentryOptionsFactory.makeScreenshotOptions()
            let photographer = SentryViewPhotographer(
                renderer: HierarchyRenderer(),
                redactOptions: options,
                enableMaskRendererV2: options.enableViewRendererV2
            )
            image = photographer.image(view: controller.view)
        } else {
            image = HierarchyRenderer().render(view: controller.view)
        }

        if let name {
            try save(image, named: name)
        }

        return try Bitmap(image)
    }

    /// Spins the run loop until the surface says it is ready to be photographed,
    /// and fails rather than photographing something that never arrived.
    ///
    /// A video surface needs this: `AVPlayerLayer` shows nothing until its item
    /// has decoded a frame, and a render taken before that would compare two
    /// empty rectangles and call the result masking.
    private static func settle(
        _ view: UIView,
        _ isSettled: @MainActor (UIView) -> Bool
    ) async throws {
        for _ in 0..<100 {
            view.layoutIfNeeded()
            if isSettled(view) { return }
            try await Task.sleep(for: .milliseconds(50))
        }

        try #require(isSettled(view), "the surface never became ready to photograph")
    }

    /// Ready when the mask marker is in the tree with a real frame and a player
    /// layer under it has a decoded frame to show.
    ///
    /// The marker half is load-bearing on its own: without it a surface that
    /// silently stopped applying `sentryMasked()` would still render two
    /// identical *player-less* rectangles and pass.
    ///
    /// One ready layer rather than all of them, because `AVPlayerViewController`
    /// builds a second `AVPlayerLayer` it never displays; that spare stays
    /// not-ready forever and would hold the wait open until it timed out.
    @MainActor
    private static func playerIsShowingItsFootage(_ view: UIView) -> Bool {
        guard let marker = view.firstDescendant(of: SentryMaskedRegionView.self),
              !marker.bounds.isEmpty
        else { return false }

        return view.layer.playerLayers.contains(where: \.isReadyForDisplay)
    }

    /// Renders a view the same way `SentryDefaultViewRenderer` does, which is the
    /// most complete of the SDK's two renderers - a mask proven against it holds
    /// for the faster one too.
    private final class HierarchyRenderer: NSObject, SentryViewRenderer {
        func render(view: UIView) -> UIImage {
            UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
        }
    }

    /// An RGBA bitmap, compared pixel by pixel.
    private struct Bitmap {
        let width: Int
        let height: Int
        private let samples: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try #require(image.cgImage, "image has no bitmap")
            width = cgImage.width
            height = cgImage.height

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
                "could not create a bitmap context"
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            samples = buffer
        }

        /// The largest absolute difference across this pixel's four channels.
        func channelDelta(to other: Bitmap, x: Int, y: Int) -> Int {
            let offset = (y * width + x) * 4
            return (0..<4).reduce(0) { worst, channel in
                max(worst, abs(Int(samples[offset + channel]) - Int(other.samples[offset + channel])))
            }
        }
    }

    private static var evidenceDirectory: URL {
        ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"].map { URL(filePath: $0) }
            ?? URL.temporaryDirectory.appending(path: "sentry-masking-evidence")
    }

    private static func save(_ image: UIImage, named name: String) throws {
        let directory = evidenceDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).png")
        try #require(image.pngData(), "masked render produced no PNG").write(to: url)
        print("masking evidence: \(url.path())")
    }

    // MARK: - Surfaces

    private static func chart(readings: some Sequence<Int>) -> some View {
        let samples = readings.enumerated().map { index, heartRate in
            HeartRateDataPoint(
                timestamp: chartStart.addingTimeInterval(TimeInterval(index) * 3),
                heartRate: heartRate
            )
        }

        return HeartRateChartView(
            heartRateData: samples,
            workoutStartTime: chartStart,
            workoutDuration: chartDuration,
            averageHeartRateBpm: 140,
            maxHeartRateBpm: 180
        )
        .padding(20)
    }

    private static func readout(bpm: String, calories: String, weight: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            monospaced("\(bpm) BPM", size: 44)
            monospaced("\(calories) cal", size: 32)
            monospaced("\(weight) lbs", size: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(Color.black)
    }

    private static func identity(displayName: String, handle: String, accountID: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            monospaced(displayName, size: 28)
            monospaced(handle, size: 18)
            monospaced(accountID, size: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(Color.black)
    }

    private static func media(_ photo: UIImage) -> some View {
        Image(uiImage: photo)
            .resizable()
            .frame(width: 300, height: 200)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(Color.black)
    }

    /// Stands in for a climber's attached photo: enough structure that mirroring
    /// it is unmistakable, and an exact pixel permutation of its own mirror.
    private static func photograph() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { context in
            for row in 0..<10 {
                for column in 0..<15 {
                    let shade = CGFloat((row * 3 + column * 17) % 256) / 255
                    UIColor(red: shade, green: 1 - shade, blue: shade / 2, alpha: 1).setFill()
                    context.fill(CGRect(x: column * 20, y: row * 20, width: 20, height: 20))
                }
            }
        }
    }

    private static func progressChart(values: [Double]) -> some View {
        let points = values.enumerated().map { index, value in
            ProgressLineChartPoint(
                id: "point-\(index)",
                date: chartStart.addingTimeInterval(TimeInterval(index) * 86_400 * 7),
                value: value,
                valueText: "\(Int(value))",
                dateText: "week \(index)"
            )
        }

        return ProgressLineChartView(
            title: "Steps",
            points: points,
            colorScheme: .dark,
            height: 260
        ) { value in
            "\(Int(value))"
        }
    }

    /// Dated back from today, because the chart plots a rolling twelve-week
    /// window and draws a maskless empty state for anything older.
    private static func weeklyStepsChart(earlierWeeks: [Int]) -> some View {
        let now = Date()
        // Index 0 is this week and is identical in both variants; the
        // permutation lands on the weeks behind it.
        let steps = [3_100] + earlierWeeks

        let workouts = steps.enumerated().map { index, weekSteps in
            ProfileWorkoutSummary(
                id: "workout-\(index)",
                name: "Empire State Building",
                startedAt: now.addingTimeInterval(TimeInterval(index) * -86_400 * 7),
                durationSeconds: 1_800,
                steps: weekSteps,
                source: .headphoneMotion,
                climbId: nil,
                climbTier: nil,
                climbCompletionStatus: nil,
                climbCompletionDurationSeconds: nil
            )
        }

        return ProfileWeeklyStepsChart(workouts: workouts).padding(16)
    }

    private static func trendChart(values: [Double]) -> some View {
        AscendTrendChart(values: values, average: 110)
            .frame(height: 160)
            .padding(16)
    }

    private static func video(_ url: URL) -> Photo {
        Photo(url: url, type: .video, duration: 1)
    }

    /// A pair of one-second movies that are mirror images of each other.
    private struct Footage {
        let original: URL
        let mirrored: URL

        func discard() {
            for url in [original, mirrored] {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func footage() async throws -> Footage {
        let frame = videoFrame()

        return Footage(
            original: try await movie(showing: frame),
            mirrored: try await movie(showing: frame.mirrored())
        )
    }

    /// The picture every frame of the fixture movie shows.
    ///
    /// Flat 32-point blocks on a 32-point grid, so the horizontal mirror maps
    /// whole macroblocks onto whole macroblocks and survives H.264 as a genuine
    /// permutation - the two movies decode to the same set of pixels, which is
    /// what lets the averaged mask fill match.
    private static func videoFrame() -> UIImage {
        UIGraphicsImageRenderer(size: videoSize).image { context in
            let columns = Int(videoSize.width) / videoBlock
            let rows = Int(videoSize.height) / videoBlock

            for row in 0..<rows {
                for column in 0..<columns {
                    let shade = CGFloat((row * 29 + column * 61) % 256) / 255
                    UIColor(red: shade, green: 1 - shade, blue: (1 - shade) / 2, alpha: 1).setFill()
                    context.fill(
                        CGRect(
                            x: column * videoBlock,
                            y: row * videoBlock,
                            width: videoBlock,
                            height: videoBlock
                        )
                    )
                }
            }
        }
    }

    private static let videoSize = CGSize(width: 320, height: 576)
    private static let videoBlock = 32

    /// Writes a real one-second movie whose every frame is `frame`.
    ///
    /// A constant movie is what makes the two renders comparable at all: two of
    /// the three player surfaces start playing by themselves, so nothing pins
    /// them to the same timestamp. Every frame is a keyframe at a bitrate high
    /// enough that the flat blocks come back out as they went in.
    private static func movie(showing frame: UIImage) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ascend-masking-evidence-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoMaxKeyFrameIntervalKey: 1
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB]
        )
        writer.add(input)
        try #require(writer.startWriting(), "could not start writing the fixture movie")
        writer.startSession(atSourceTime: .zero)

        let cgFrame = try #require(frame.cgImage, "the fixture frame has no bitmap")

        for index in 0..<12 {
            let pool = try #require(adaptor.pixelBufferPool, "the writer produced no pixel buffer pool")
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixelBuffer = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: Int(videoSize.width),
                height: Int(videoSize.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                context.draw(cgFrame, in: CGRect(origin: .zero, size: videoSize))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 12))
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// Monospaced so a reordering of the same characters renders to exactly the
    /// same width, leaving the masked rectangle in exactly the same place.
    private static func monospaced(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
    }
}

private extension UIImage {
    /// A left-to-right mirror: the same pixels, rearranged.
    func mirrored() -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            draw(at: .zero)
        }
    }
}

private extension UIView {
    /// The first view of `type` in this subtree, self included.
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}

private extension CALayer {
    /// Every `AVPlayerLayer` in this layer tree, self included.
    var playerLayers: [AVPlayerLayer] {
        var found = (self as? AVPlayerLayer).map { [$0] } ?? []
        for sublayer in sublayers ?? [] {
            found.append(contentsOf: sublayer.playerLayers)
        }
        return found
    }
}
