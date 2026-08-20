import AVFoundation
import AVKit
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Proves that masking a surface for Sentry does not cost the climber a touch.
///
/// `View.sentryMasked()` overlays a full-frame `UIViewRepresentable` on top of
/// surfaces that are interactive: chart scrubbing, video transport controls, the
/// share composer's pan and pinch. `allowsHitTesting(false)` and
/// `isUserInteractionEnabled = false` cover the marker itself, but SwiftUI hosts
/// a representable inside platform views of its own, and a host that claims a
/// touch swallows it in silence - no crash, no log, just a chart that stops
/// scrubbing.
///
/// `UIView.hitTest` is the assertion because it is the mechanism: UIKit resolves
/// the touch target that way before delivering anything, so a target that is the
/// content is a touch that reaches the content, and a target inside the mask's
/// own view chain is a touch that never will be.
///
/// Three levels, weakest last:
///
/// 1. **The marker answers for itself.** `SentryMaskedRegionView` refuses every
///    point in its own bounds while still reporting a real, non-empty frame -
///    both asserted together, because passing the touch test by shrinking the
///    mask would be a privacy regression wearing an interaction fix's clothes.
/// 2. **The overlay is inert all the way up.** Every platform view SwiftUI
///    builds to host the marker is asked, directly, to hit-test each point in
///    its own frame, and must refuse all of them. That is the exact risk this
///    suite exists for, and it is worth asking rather than assuming: SwiftUI
///    leaves `isUserInteractionEnabled` **true** on
///    `UIKitPlatformViewHost<PlatformViewRepresentableAdaptor<...>>`, so the
///    pass-through is its `hitTest` honouring `allowsHitTesting(false)` and not
///    the flag. Asking the host itself is stronger than reading the window's
///    answer, which only shows that something else happened to win.
/// 3. **A real control under the mask is still the target.** A `UIButton`
///    beneath `sentryMasked()` wins every probe point, identically masked and
///    unmasked. On the three player surfaces the content underneath is UIKit
///    too, so their sweep genuinely distinguishes "reached the video" from
///    "swallowed by the mask".
///
/// **Coverage is not uniform across the seven surfaces. Read this before
/// treating a green suite as proof that a chart still scrubs.**
///
/// *Covered end to end* - `VideoPlayerView`, `LoopingVideoView`,
/// `FullScreenVideoPlayer`. Real UIKit content sits under the mask, so a probe
/// resolving to that content is a touch arriving where it was aimed.
///
/// *Covered structurally only* - `HeartRateChartView`, `ProgressLineChartView`,
/// `ProfileWeeklyStepsChart`, `AscendTrendChart`. What the sweep proves on these
/// is that the marker and its SwiftUI platform host refuse `hitTest` across
/// their own frames - the risk the mask itself introduces. What it does **not**
/// prove is that the chart still scrubs: Swift Charts draws no `UIView` under
/// the mask, so a SwiftUI-level swallow inside SwiftUI's own hit-test walk would
/// resolve to the same hosting view as a healthy chart and pass unnoticed.
///
/// There is no behavioural assertion because the harness cannot express one.
/// SwiftUI gestures on a hosting view are keyed to real UIKit event identity;
/// synthetic `UITouch`/`UIEvent` delivery was tried four ways -
/// `UIWindow.sendEvent`, `UIApplication.sendEvent`, the responder's own
/// `touchesBegan`, and every recognizer on the chain - and the handler never
/// fired *even with no mask present*. Closing it needs a UI test target, which
/// has been declined for this branch. Do not re-attempt synthetic delivery.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct SentryMaskInteractionTests {
    private static let surfaceSize = CGSize(width: 393, height: 640)

    // MARK: - The marker itself

    /// The mask must be simultaneously untouchable and geometrically real. If a
    /// future edit ever wins the interaction half by shrinking or emptying the
    /// frame, redaction has nothing to paint and the leak this whole mechanism
    /// exists to close reopens silently.
    @Test
    func theMarkerRefusesEveryTouchWithoutGivingUpItsFrame() {
        let marker = SentryMaskedRegionView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))

        #expect(!marker.isUserInteractionEnabled)
        #expect(!marker.bounds.isEmpty, "a mask with no frame covers nothing")

        for point in Self.gridPoints(in: marker.bounds) {
            #expect(marker.point(inside: point, with: nil), "the mask no longer covers \(point)")
            #expect(marker.hitTest(point, with: nil) == nil, "the mask claimed a touch at \(point)")
        }
    }

    // MARK: - The modifier itself

    @Test
    func aTouchOverTheMaskStillResolvesToTheControlUnderneath() async throws {
        let masked = try await Self.probeTheButton(under: Self.probeSurface(masked: true))
        let unmasked = try await Self.probeTheButton(under: Self.probeSurface(masked: false))

        #expect(masked.maskedRegionCount == 1, "the probe surface is not actually masked")
        #expect(unmasked.maskedRegionCount == 0, "the unmasked control is masked too, so it proves nothing")
        #expect(masked.probeCount > 0 && masked.probeCount == unmasked.probeCount)

        // Control: the button really is the answer when nothing is over it.
        #expect(
            unmasked.strayTargets.isEmpty,
            "the harness is wrong: without a mask the button is not the target either (\(unmasked.strayTargets))"
        )

        #expect(
            masked.strayTargets.isEmpty,
            """
            The mask swallowed a touch meant for the control beneath it - \(masked.strayTargets.count) of \
            \(masked.probeCount) probes landed on \(Set(masked.strayTargets).sorted()) instead of the button. \
            Fix View+SentryMasked.swift so the overlay is transparent to hit-testing - never by weakening the \
            masking SentryMaskingEvidenceTests proves.
            """
        )
    }

    // MARK: - Every shipped surface that carries the mask

    @Test
    func theHeartRateChartStaysScrubbable() async throws {
        try await Self.expectNoTouchSwallowed(by: Self.heartRateChart(), named: "HeartRateChartView")
    }

    @Test
    func theProgressLineChartStaysScrubbable() async throws {
        try await Self.expectNoTouchSwallowed(by: Self.progressLineChart(), named: "ProgressLineChartView")
    }

    @Test
    func theProfileWeeklyStepsChartStaysTappable() async throws {
        try await Self.expectNoTouchSwallowed(
            by: ProfileWeeklyStepsChart(workouts: Self.profileWorkouts()).padding(16),
            named: "ProfileWeeklyStepsChart"
        )
    }

    @Test
    func theTrendChartDoesNotClaimTouchesMeantForItsCard() async throws {
        try await Self.expectNoTouchSwallowed(
            by: AscendTrendChart(values: (0..<24).map { Double(90 + ($0 * 7) % 40) }, average: 110)
                .frame(height: 160)
                .padding(16),
            named: "AscendTrendChart"
        )
    }

    @Test
    func aWorkoutCardVideoStaysTappable() async throws {
        let url = try await Self.videoFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try await Self.expectNoTouchSwallowed(
            by: VideoPlayerView(player: AVPlayer(url: url)).frame(height: 300),
            named: "VideoPlayerView"
        )
    }

    @Test
    func theShareComposerVideoBackgroundStaysPannable() async throws {
        let url = try await Self.videoFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try await Self.expectNoTouchSwallowed(
            by: ShareBackgroundView(source: .video(url)),
            named: "ShareBackgroundView(.video)"
        )
    }

    /// The one surface whose interaction is not ours to observe even in
    /// principle: the transport controls belong to `AVPlayerViewController`, so
    /// the reachable assertion is that touches land inside its own view tree
    /// rather than on the mask.
    @Test
    func fullScreenVideoTransportControlsStayReachable() async throws {
        let url = try await Self.videoFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try await Self.expectNoTouchSwallowed(
            by: FullScreenPhotoView(photo: Photo(url: url, type: .video, duration: 1), onDismiss: {}),
            named: "FullScreenPhotoView(video)",
            // The player is loaded asynchronously, so the mask it carries only
            // enters the hierarchy once that resolves.
            awaitingMask: true
        )
    }

    // MARK: - The assertion

    /// Hosts `view` and sweeps every masked region it renders, asserting no probe
    /// point resolves into the mask's own view chain.
    private static func expectNoTouchSwallowed(
        by view: some View,
        named name: String,
        awaitingMask: Bool = false
    ) async throws {
        try await hosting(view, awaitingMask: awaitingMask) { window, root in
            let markers = root.descendants(of: SentryMaskedRegionView.self)
            try #require(
                !markers.isEmpty,
                "\(name) rendered no SentryMaskedRegionView, so this test is not covering the mask it claims to"
            )

            for marker in markers {
                let swallowers = maskOnlyChain(from: marker, stoppingAt: root)
                try #require(
                    !marker.bounds.isEmpty,
                    "\(name) rendered a zero-sized mask, which covers nothing"
                )

                // The structural half, asked of each mask-only view directly
                // rather than inferred from what won at the window: no view that
                // exists solely to carry the marker may claim any point in its
                // own frame. SwiftUI leaves `isUserInteractionEnabled` true on
                // the platform host it wraps a representable in, so the host's
                // refusal is a hit-test answer and has to be read as one.
                for swallower in swallowers {
                    for point in gridPoints(in: swallower.bounds) {
                        #expect(
                            swallower.hitTest(point, with: nil) == nil,
                            """
                            \(name): \(type(of: swallower)) carries the Sentry mask and claimed a touch at \
                            \(point) in its own frame, so UIKit can route to it instead of to the surface \
                            underneath.
                            """
                        )
                    }
                }

                for point in probePoints(in: marker, within: window) {
                    let hit = window.hitTest(point, with: nil)

                    #expect(
                        hit != nil,
                        "\(name): a touch at \(point) resolved to nothing, so it reaches no handler at all"
                    )

                    guard let hit else { continue }
                    #expect(
                        !swallowers.contains(where: { $0 === hit || hit.isDescendant(of: $0) }),
                        """
                        \(name): a touch at \(point) was claimed by \(type(of: hit)), which belongs to the \
                        Sentry mask overlay rather than to the surface underneath it. The mask is swallowing \
                        touches. Fix View+SentryMasked.swift without weakening what SentryMaskingEvidenceTests \
                        proves.
                        """
                    )
                }
            }
        }
    }

    /// The views a touch must never land on: the marker, plus the platform views
    /// SwiftUI created solely to host it.
    ///
    /// An ancestor qualifies only if it is both the marker's single-child parent
    /// *and* a SwiftUI platform view host. Single-child alone is not enough:
    /// Swift Charts drawing straight into `CALayer`s with no `UIView` subviews
    /// would leave the mask host as the overlay container's only child, and the
    /// walk would climb into a content-bearing ancestor whose `hitTest`
    /// legitimately returns itself - failing this suite over something that is
    /// not the mask. Narrowing on a rename costs coverage the window sweep still
    /// carries; over-extending costs a false failure.
    private static func maskOnlyChain(from marker: UIView, stoppingAt root: UIView) -> [UIView] {
        var chain = [marker]
        var node = marker

        while chain.count <= maximumMaskHostDepth,
              let parent = node.superview,
              parent !== root,
              parent.subviews.count == 1,
              isPlatformViewHost(parent) {
            chain.append(parent)
            node = parent
        }

        return chain
    }

    /// SwiftUI wraps a `UIViewRepresentable` in one
    /// `UIKitPlatformViewHost<PlatformViewRepresentableAdaptor<...>>`; the cap is
    /// slack for a release that nests another.
    private static let maximumMaskHostDepth = 3

    private static func isPlatformViewHost(_ view: UIView) -> Bool {
        "\(type(of: view))".contains("PlatformViewHost")
    }

    /// A grid across `bounds`, in its own coordinate space.
    private static func gridPoints(in bounds: CGRect, steps: Int = 5) -> [CGPoint] {
        (0..<steps).flatMap { row in
            (0..<steps).map { column in
                CGPoint(
                    x: bounds.minX + bounds.width * (Double(column) + 0.5) / Double(steps),
                    y: bounds.minY + bounds.height * (Double(row) + 0.5) / Double(steps)
                )
            }
        }
    }

    /// A grid across the masked region, in window coordinates. A mask that
    /// swallows only its edges - a host inset by a point or two - still costs a
    /// touch, so the sweep covers the frame rather than sampling its centre.
    private static func probePoints(in view: UIView, within window: UIWindow, steps: Int = 5) -> [CGPoint] {
        let bounds = view.bounds
        guard !bounds.isEmpty else { return [] }

        return gridPoints(in: bounds, steps: steps)
            .map { view.convert($0, to: window) }
            .filter { window.bounds.contains($0) }
    }

    // MARK: - Hosting

    private struct ProbeResult {
        /// Named by class, because whatever claimed the touch is not the object
        /// the assertion was holding.
        let strayTargets: [String]
        let probeCount: Int
        let maskedRegionCount: Int
    }

    /// Sweeps the probe button and reports every point that did not resolve to
    /// the button itself. Identity rather than class, so no naming subtlety can
    /// turn a swallowed touch into a pass.
    private static func probeTheButton(under view: some View) async throws -> ProbeResult {
        var strayTargets: [String] = []
        var probeCount = 0
        var maskedRegionCount = 0

        try await hosting(view) { window, root in
            let button = try #require(
                root.descendants(of: SentryProbeButton.self).first,
                "the probe button never reached the hierarchy"
            )
            maskedRegionCount = root.descendants(of: SentryMaskedRegionView.self).count

            let points = probePoints(in: button, within: window)
            probeCount = points.count
            strayTargets = points.compactMap { point in
                let hit = window.hitTest(point, with: nil)
                guard hit !== button else { return nil }
                return hit.map { "\(type(of: $0))" } ?? "nothing"
            }
        }

        return ProbeResult(
            strayTargets: strayTargets,
            probeCount: probeCount,
            maskedRegionCount: maskedRegionCount
        )
    }

    /// Puts `view` in the shared window scene, lets SwiftUI commit its platform
    /// views, and hands the laid-out hierarchy to `body`.
    private static func hosting(
        _ view: some View,
        awaitingMask: Bool = false,
        _ body: (UIWindow, UIView) throws -> Void
    ) async throws {
        let controller = UIHostingController(
            rootView: view
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .transaction { $0.disablesAnimations = true }
        )
        controller.view.frame = CGRect(origin: .zero, size: surfaceSize)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: surfaceSize))
        window.frame = CGRect(origin: .zero, size: surfaceSize)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))

        if awaitingMask {
            for _ in 0..<40 where controller.view.descendants(of: SentryMaskedRegionView.self).isEmpty {
                try await Task.sleep(for: .milliseconds(100))
                controller.view.layoutIfNeeded()
            }
        }

        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        controller.view.layoutIfNeeded()

        try body(window, controller.view)
    }

    // MARK: - Surfaces

    /// A control with exactly one correct hit-test answer, so "the mask changed
    /// nothing" is a comparison rather than a judgement call.
    @ViewBuilder
    private static func probeSurface(masked: Bool) -> some View {
        let button = ProbeButtonRepresentable()
            .frame(width: 300, height: 220)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if masked {
            button.sentryMasked()
        } else {
            button
        }
    }

    private static func heartRateChart() -> some View {
        let start = Date(timeIntervalSince1970: 1_750_300_000)
        let samples = (0..<600).map { second in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(second) * 3),
                heartRate: 100 + Int((sin(Double(second) / 37) * 40).rounded())
            )
        }

        return HeartRateChartView(
            heartRateData: samples,
            workoutStartTime: start,
            workoutDuration: 1_800,
            averageHeartRateBpm: 140,
            maxHeartRateBpm: 180
        )
        .padding(20)
    }

    private static func progressLineChart() -> some View {
        let start = Date(timeIntervalSince1970: 1_750_300_000)
        let points = (0..<12).map { index in
            ProgressLineChartPoint(
                id: "point-\(index)",
                date: start.addingTimeInterval(TimeInterval(index) * 86_400 * 7),
                value: Double(2_000 + index * 130),
                valueText: "\(2_000 + index * 130)",
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
    /// window and draws its empty state - which carries no mask - for anything
    /// older.
    private static func profileWorkouts() -> [ProfileWorkoutSummary] {
        let start = Date()

        return (0..<10).map { index in
            ProfileWorkoutSummary(
                id: "workout-\(index)",
                name: "Empire State Building",
                startedAt: start.addingTimeInterval(TimeInterval(index) * -86_400 * 7),
                durationSeconds: 1_800,
                steps: 2_400 + index * 90,
                source: .headphoneMotion,
                climbId: nil,
                climbTier: nil,
                climbCompletionStatus: nil,
                climbCompletionDurationSeconds: nil
            )
        }
    }

    /// A real one-second movie on disk. `FullScreenPhotoView` asks
    /// `RemoteMediaLoader` whether the asset is playable before it builds the
    /// player, so a stub URL never reaches the masked player at all.
    private static func videoFile(size: CGSize = CGSize(width: 320, height: 568)) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ascend-mask-interaction-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB]
        )
        writer.add(input)
        try #require(writer.startWriting(), "could not start writing the fixture movie")
        writer.startSession(atSourceTime: .zero)

        for index in 0..<12 {
            let pool = try #require(adaptor.pixelBufferPool, "the writer produced no pixel buffer pool")
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixelBuffer = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                context.setFillColor(UIColor.darkGray.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
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
}

/// The one view a probe touch is allowed to land on.
private final class SentryProbeButton: UIButton {}

private struct ProbeButtonRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SentryProbeButton {
        let button = SentryProbeButton(type: .custom)
        button.backgroundColor = .systemBlue
        return button
    }

    func updateUIView(_ uiView: SentryProbeButton, context: Context) {}
}

private extension UIView {
    /// Every view of `type` in this subtree, self included.
    func descendants<T: UIView>(of type: T.Type) -> [T] {
        var found = (self as? T).map { [$0] } ?? []
        for subview in subviews {
            found.append(contentsOf: subview.descendants(of: type))
        }
        return found
    }
}
