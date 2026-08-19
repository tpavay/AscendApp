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
/// backwards. Monospaced type and identical image dimensions keep the layout
/// pixel-for-pixel identical, and a permutation has the same average colour -
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
/// The masked renders are written out for the record; set `ASCEND_EVIDENCE_DIR`
/// to collect them somewhere durable.
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
        named name: String
    ) async throws {
        let rawDifference = try await difference(render(first, masked: false), render(second, masked: false))
        let maskedDifference = try await difference(
            render(first, masked: true, savedAs: "\(name)-a"),
            render(second, masked: true, savedAs: "\(name)-b")
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
        savedAs name: String? = nil
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
