import Foundation
import SwiftUI
import Testing
import UIKit
import Vision

/// The one way a test puts a screen on the simulator and reads it back.
///
/// Every render suite used to host a full screen in its own `UIWindow`, settle it with its own
/// loop, `drawHierarchy` it at scale 3 (1179x2556, 12 MB a bitmap), PNG-encode it, and in the
/// copy-presence case hand the bitmap to Vision - twenty-three private `recognizedText` copies
/// across the target. The host never gives that memory back between tests, so fourteen suites
/// peaked over 1 GB and the CI job could not run the suite in one process.
///
/// This helper hosts, settles, and returns **facts**: the strings on screen with their frames,
/// the colour at a point, the frame of a named element. No `UIImage` or `ImageRenderer` output
/// leaves it. A bitmap is made only inside the call that needs one, at the scale that call needs -
/// 1x for a colour or a position, the caller's scale for glyph legibility - and is released when
/// the call returns. The 3x photograph the captain reviews is written only when
/// `ASCEND_EVIDENCE_DIR` is set; CI never sets it and discarded every photograph it took before.
///
/// Presence and absence of copy are proved from the accessibility tree
/// (`AccessibilityAutomationSupport`), which fails on a missing, hidden, or off-screen label the
/// way OCR did. OCR stays available through `recognizedText(scale:)` for the tests whose contract
/// is legibility - an accessibility text size, "every line reachable", the Sentry mask proof.
@MainActor
enum RenderedScreen {
    /// The logical size of the iPhone 16 Pro the evidence suites render at.
    static let iPhone16ProSize = CGSize(width: 402, height: 874)

    /// How long `host` waits for the hosted hierarchy to settle before handing it over.
    enum Settle {
        /// `turns` passes of layout with `interval` between them. The historic default: twelve
        /// 50 ms turns, which every private helper used and every hosted surface is known to
        /// settle within.
        case turns(Int, interval: Duration = .milliseconds(50))
        /// Layout turns until `isReady` holds, failing after `turns` of them. For a surface with
        /// an asynchronous arrival - a decoded video frame, a loaded model - where photographing
        /// early would compare two empty rectangles.
        case until(turns: Int = 100, interval: Duration = .milliseconds(50), isReady: @MainActor (UIView) -> Bool)
    }

    /// Hosts `view` in the shared window scene, settles it, and hands `body` a handle that reads
    /// facts off it. The window is hidden and its root view controller dropped on every path.
    ///
    /// The accessibility runtime is on for the duration, so `body` can walk the tree. Any suite
    /// calling this must carry `.hostsAWindow`: the host has one window scene and two suites
    /// bringing theirs up at once push each other out of the hierarchy.
    static func host<Result>(
        _ view: some View,
        size: CGSize = iPhone16ProSize,
        interfaceStyle: UIUserInterfaceStyle = .dark,
        settle: Settle = .turns(12),
        _ body: @MainActor (HostedScreen) async throws -> Result
    ) async throws -> Result {
        try await host(
            HelperOwned(UIHostingController(rootView: view)),
            size: size,
            interfaceStyle: interfaceStyle,
            settle: settle,
            body
        )
    }

    /// The same, for a screen a test already built as a view controller.
    static func host<Result>(
        _ controller: UIViewController,
        size: CGSize = iPhone16ProSize,
        interfaceStyle: UIUserInterfaceStyle = .dark,
        settle: Settle = .turns(12),
        _ body: @MainActor (HostedScreen) async throws -> Result
    ) async throws -> Result {
        // The caller's frame keeps this controller alive past the wait below, so there is nothing
        // to wait for beyond the run-loop turns SwiftUI needs to let go of the window.
        try await host(HelperOwned(controller, isOwnedByCaller: true), size: size, interfaceStyle: interfaceStyle, settle: settle, body)
    }

    /// A hosting controller and whether the helper is the only thing holding it. The strong
    /// reference is dropped before `dismantle` waits, and the wait watches the weak one, so a
    /// helper-made controller can actually deallocate inside that wait - with the reference
    /// held in a parameter it never could, and the wait measured nothing.
    private final class HelperOwned {
        var controller: UIViewController?
        weak var hosted: UIViewController?
        let isOwnedByCaller: Bool
        init(_ controller: UIViewController, isOwnedByCaller: Bool = false) {
            self.controller = controller
            self.hosted = controller
            self.isOwnedByCaller = isOwnedByCaller
        }

        /// Whether the wait still has something to watch: a helper-owned controller that has not
        /// deallocated yet. A caller-owned controller is never watched.
        var isStillHosted: Bool { !isOwnedByCaller && hosted != nil }
    }

    private static func host<Result>(
        _ owned: HelperOwned,
        size: CGSize,
        interfaceStyle: UIUserInterfaceStyle,
        settle: Settle,
        _ body: @MainActor (HostedScreen) async throws -> Result
    ) async throws -> Result {
        let bounds = CGRect(origin: .zero, size: size)
        // A window with no scene is never handed to the render server, and `drawHierarchy` then
        // captures an empty surface - so borrow the test host's own scene.
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "no UIWindowScene is connected, so nothing hosted here would ever be drawn"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.overrideUserInterfaceStyle = interfaceStyle
        window.backgroundColor = interfaceStyle == .light ? .white : .black

        // The strong reference to the controller lives only inside `mount`, so that once `body`
        // has returned and `owned` has let go, the dismantle wait below is waiting on the last
        // reference the helper holds rather than on its own local.
        func mount() async throws -> Result {
            let controller = owned.controller!
            controller.overrideUserInterfaceStyle = interfaceStyle
            controller.view.frame = bounds
            window.rootViewController = controller

            window.makeKeyAndVisible()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            window.layoutIfNeeded()

            return try await withAccessibilityAutomation {
                try await Self.settle(window, settle)
                return try await body(HostedScreen(window: window, root: controller.view))
            }
        }

        let result: Result
        do {
            result = try await mount()
        } catch {
            owned.controller = nil
            await dismantle(window, watching: owned)
            throw error
        }
        owned.controller = nil
        await dismantle(window, watching: owned)
        return result
    }

    /// Takes the window out of the scene and lets SwiftUI finish dismantling what it hosted.
    ///
    /// Detaching from the scene is what dismantles the content; hiding alone is not enough. And
    /// the dismantling is not synchronous: a hosted `@Query` keeps observing SwiftData for a beat
    /// after its window is gone, and the next test's `ModelContext.save()` - on a container of its
    /// own - then calls out to that observer and never returns. Both the BEFORE and the AFTER
    /// one-host runs of the whole suite wedged exactly there, ~250 suites in, with the host alive
    /// at 0% CPU: the silent-hang signature `iOS Verify (Staging)` shows. Two run-loop turns cost
    /// 40 ms a host and give the observer its beat.
    private static func dismantle(_ window: consuming UIWindow, watching owned: HelperOwned) async {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
        // The window keeps a hand on the controller it just hosted until it is itself released,
        // so it is let go here, before the wait, rather than when the caller's frame unwinds.
        _ = consume window
        // Two turns at least; up to half a second for the hosting controller the helper built to
        // actually deallocate, which is when SwiftUI drops its `@Query` observers. A controller the
        // caller built and still holds cannot deallocate here (`isStillHosted` is false then), so
        // the wait is bounded. A `@Query` that outlives this wait anyway is why every container a hosted
        // screen reads comes from `RetainedModelContainer`.
        // UIKit lets go of the controller on its own schedule after the window is gone - measured
        // at the return of `host`, not inside this wait, so a controller still alive here is not a
        // leak and is not reported as one.
        for turn in 0..<25 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
            if turn >= 1, !owned.isStillHosted { return }
        }
    }

    /// Lays `view` out off screen and hands `body` its pixels at `scale`, released on return.
    ///
    /// For the suites that never needed a window: a share card, a sticker, a chart. `scale` is 1
    /// unless the assertion is about glyphs; a colour or a position reads the same at 1x and
    /// costs a ninth of the memory.
    static func withOffscreenPixels<Result>(
        of view: some View,
        scale: CGFloat = 1,
        proposedSize: ProposedViewSize? = nil,
        _ body: (PixelSampler) throws -> Result
    ) throws -> Result {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let proposedSize {
            renderer.proposedSize = proposedSize
        }
        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        return try body(try PixelSampler(image))
    }

    /// Vision's reading of `view` laid out off screen at `scale`, lowercased and joined with
    /// spaces. Only for a test whose contract is that the glyphs rendered legibly.
    static func recognizedText(
        of view: some View,
        scale: CGFloat,
        proposedSize: ProposedViewSize? = nil
    ) async throws -> String {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let proposedSize {
            renderer.proposedSize = proposedSize
        }
        let cgImage = try #require(renderer.cgImage, "ImageRenderer produced no image")
        return try await recognizeText(in: cgImage)
    }

    /// Writes `view`, laid out off screen at 3x, to `ASCEND_EVIDENCE_DIR` as `name`.png - and does
    /// nothing at all when that variable is unset. The reviewer-facing proof sheets go through
    /// here so a CI run never lays them out.
    @discardableResult
    static func photograph(
        _ view: some View,
        named name: String,
        scale: CGFloat = 3,
        proposedSize: ProposedViewSize? = nil
    ) throws -> URL? {
        guard let directory = evidenceDirectory else { return nil }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let proposedSize {
            renderer.proposedSize = proposedSize
        }
        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        return try write(image, named: name, in: directory)
    }

    /// Where photographs go, or nil when this run keeps none.
    static var evidenceDirectory: URL? {
        ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"].map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }
    }

    /// Whether this run writes photographs. A test that exists only to produce one skips its
    /// render entirely when this is false, and asserts on the tree instead.
    static var isPhotographing: Bool { evidenceDirectory != nil }

    // MARK: - Internals shared by both paths

    fileprivate static func settle(_ window: UIWindow, _ settle: Settle) async throws {
        switch settle {
        case .turns(let turns, let interval):
            for _ in 0..<turns {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(for: interval)
            }
        case .until(let turns, let interval, let isReady):
            for _ in 0..<turns {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                if isReady(window) { return }
                try await Task.sleep(for: interval)
            }
            try #require(isReady(window), "the hosted surface never became ready")
        }
    }

    fileprivate static func recognizeText(in cgImage: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    fileprivate static func write(_ image: UIImage, named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name.hasSuffix(".png") ? name : "\(name).png")
        let png = try #require(image.pngData(), "the photograph produced no PNG data")
        try png.write(to: url)
        #expect(png.count > 5_000, "\(name) rendered as a near-empty image")
        print("ASCEND_EVIDENCE_FILE: \(url.path())")
        return url
    }
}

/// A screen `RenderedScreen.host` put up, read as facts.
@MainActor
struct HostedScreen {
    /// The window, for a test that scrolls, activates a control, or finds a platform view.
    let window: UIWindow
    /// The hosted root view.
    let root: UIView

    var bounds: CGRect { window.bounds }

    /// Another round of settling, for a test that changes the screen's state after hosting it.
    func settle(_ settle: RenderedScreen.Settle = .turns(12)) async throws {
        try await RenderedScreen.settle(window, settle)
    }

    // MARK: - Copy, from the accessibility tree

    /// Every piece of text the screen publishes and that is actually inside the window, once the
    /// tree has settled. A label pushed off screen, hidden, or never rendered is not here.
    ///
    /// A screen that publishes nothing before `isReady` holds is recorded as an issue rather than
    /// returned as an empty list: every absence assertion (`!copy().contains(...)`) would pass
    /// against an empty tree, so an empty read that was still waiting for content has to be a
    /// failure, never a vacuous proof. A test that expects the screen to be empty says so with a
    /// readiness closure that accepts it (`{ _ in true }`).
    ///
    /// Every entry is also *painted*: a 1x capture of the settled screen has ink inside the
    /// element's frame. The tree reports the control, not its glyphs - a label pushed off screen
    /// or clipped to nothing inside a button still publishes the button's frame - so without this
    /// an unpainted label would read as present. With it, `copy()` reads what OCR read: text that
    /// is actually on the screen.
    func texts(
        reading budget: Int = 250,
        until isReady: ([OnScreenText]) -> Bool = { $0.isEmpty == false }
    ) async throws -> [OnScreenText] {
        // The tree and the pixels arrive on different schedules: a label is published the
        // moment SwiftUI commits it and painted a beat later, and under a busy main actor that
        // beat stretches. So a read that returned the first non-empty tree - the way the walk
        // alone did - handed back a screen with its options mid-fade and dropped exactly the
        // labels still animating in. Each read here walks the tree, captures once at 1x, and
        // keeps only what is painted; the read is ready when the caller's predicate holds on
        // the painted set AND every published text is painted, or when the painted set has
        // stopped changing for a while - a label that stays unpainted is not arriving, and the
        // caller's assertion is what should say so, at the cost of a short wait rather than
        // the whole budget.
        var remainingReads = max(1, budget)
        var stableReads = 0
        var lastPainted: [String] = []
        var elements: [NSObject] = []
        var published: [OnScreenText] = []
        var painted: [OnScreenText] = []

        while true {
            elements = accessibilityElements(under: window)
            published = Self.onScreenTexts(from: elements, in: window.bounds)
            painted = try withPixels { pixels in published.filter { pixels.hasInk(in: $0.frame) } }
            remainingReads -= 1

            let names = painted.map(\.text)
            stableReads = names == lastPainted ? stableReads + 1 : 0
            lastPainted = names

            let ready = isReady(painted)
            if ready, painted.count == published.count { break }
            if ready, stableReads >= Self.stableReadsBeforeAcceptingUnpainted { break }
            if remainingReads == 0 { break }

            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }

        if painted.count < published.count {
            let unpainted = published.filter { text in !painted.contains { $0.frame == text.frame && $0.text == text.text } }
            let report = try withPixels { pixels in
                unpainted.map { text in
                    "\(text.text) frame=\(text.frame.integral) \(pixels.inkReport(in: text.frame))"
                }
            }
            print("RenderedScreen: \(unpainted.count) published text(s) never painted: \(report) window=\(window.frame.integral) screen=\(window.screen.bounds.integral) key=\(window.isKeyWindow)")
            if let directory = ProcessInfo.processInfo.environment["ASCEND_PAINT_DEBUG_DIR"] {
                let url = URL(filePath: directory, directoryHint: .isDirectory)
                    .appending(path: "unpainted-\(Int(Date().timeIntervalSince1970 * 1000)).png")
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? capture(scale: 1).pngData()?.write(to: url)
                print("RenderedScreen: capture written to \(url.path())")
            }
        }
        if painted.isEmpty, !isReady(painted) {
            Issue.record(
                """
                The hosted screen published no on-screen text within \(budget) reads and the read \
                was still waiting for some. An absence assertion against an empty tree proves \
                nothing, so this is a failure, not an empty result. Elements found: \(elements.count).
                """
            )
        }
        return painted
    }

    /// How many consecutive reads the painted set must hold still before a read that is
    /// otherwise ready stops waiting for the texts the tree publishes but the screen has not
    /// painted. Twenty-five reads is over half a second on a quiet host - longer than a SwiftUI
    /// default animation - and a good deal more under contention, which is when it matters.
    private static let stableReadsBeforeAcceptingUnpainted = 25

    /// The screen's copy the way OCR used to hand it back: every on-screen label and value,
    /// lowercased, joined with spaces. `copy().contains("...")` is the presence proof;
    /// `!copy().contains("...")` the absence proof.
    func copy(
        reading budget: Int = 250,
        until isReady: (String) -> Bool = { $0.isEmpty == false }
    ) async throws -> String {
        let texts = try await texts(reading: budget) { isReady(Self.joined($0)) }
        return Self.joined(texts)
    }

    /// The first on-screen text containing `fragment`, case-insensitively, waiting for it to
    /// arrive. Nil when the budget is spent without it.
    func text(containing fragment: String, reading budget: Int = 250) async throws -> OnScreenText? {
        let texts = try await texts(reading: budget) { texts in
            texts.contains { $0.text.localizedCaseInsensitiveContains(fragment) }
        }
        return texts.first { $0.text.localizedCaseInsensitiveContains(fragment) }
    }

    /// The accessibility elements themselves, for a test that needs traits or activation.
    func elements(
        reading budget: Int = 250,
        until isReady: ([NSObject]) -> Bool = { $0.isEmpty == false }
    ) async throws -> [NSObject] {
        try await settledAccessibilityElements(under: window, reading: budget, until: isReady)
    }

    /// The on-screen frame of the first element whose label contains `label`, in window points.
    func frame(ofElementLabelled label: String, reading budget: Int = 250) async throws -> CGRect? {
        try await text(containing: label, reading: budget)?.frame
    }

    // MARK: - Pixels

    /// Hands `body` the screen's pixels at `scale`, released when it returns. 1x unless the read
    /// is about glyph shapes; a colour, a band, or a column reads the same at any scale.
    func withPixels<Result>(scale: CGFloat = 1, _ body: (PixelSampler) throws -> Result) throws -> Result {
        try body(try PixelSampler(capture(scale: scale)))
    }

    /// The colour at `point`, in window points, read off a 1x capture.
    func color(at point: CGPoint) throws -> RGBA {
        try withPixels { $0.color(at: point) }
    }

    // MARK: - Legibility

    /// Vision's reading of the screen at `scale`, lowercased and joined with spaces. Only for a
    /// test whose contract is that the glyphs rendered legibly - at an accessibility text size,
    /// through a mask, on every line of a scrolled surface. Presence and absence use `copy()`.
    func recognizedText(scale: CGFloat) async throws -> String {
        let cgImage = try #require(capture(scale: scale).cgImage, "the capture had no CGImage")
        return try await RenderedScreen.recognizeText(in: cgImage)
    }

    // MARK: - The photograph

    /// Writes the 3x photograph to `ASCEND_EVIDENCE_DIR` as `name`.png, and does nothing when the
    /// variable is unset. The screen is not even drawn then.
    @discardableResult
    func photograph(named name: String, scale: CGFloat = 3) throws -> URL? {
        guard let directory = RenderedScreen.evidenceDirectory else { return nil }
        return try RenderedScreen.write(capture(scale: scale), named: name, in: directory)
    }

    // MARK: - Internals

    private func capture(scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    private static func onScreenTexts(from elements: [NSObject], in bounds: CGRect) -> [OnScreenText] {
        elements.compactMap { element in
            guard !element.accessibilityElementsHidden else { return nil }
            let frame = element.accessibilityFrame
            guard frame.width > 0, frame.height > 0, bounds.intersects(frame) else { return nil }
            let traits = element.accessibilityTraits
            // A symbol's name is not copy: OCR never read "checkmark" off a glyph.
            guard !traits.contains(.image) else { return nil }
            let label = element.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = element.accessibilityValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = [label, value].filter { !$0.isEmpty }.joined(separator: " ")
            guard !text.isEmpty else { return nil }
            return OnScreenText(text: text, frame: frame, traits: traits)
        }
    }

    private static func joined(_ texts: [OnScreenText]) -> String {
        texts.map(\.text).joined(separator: " ").lowercased()
    }
}

/// One published string with the frame it occupies on screen.
struct OnScreenText: Sendable {
    let text: String
    let frame: CGRect
    let traits: UIAccessibilityTraits
}

/// One pixel, 8 bits a channel.
struct RGBA: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    /// Rec. 601 luma, 0...255.
    var luminance: Double {
        0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
    }

    /// Within `tolerance` of `other` on every channel.
    func isClose(to other: RGBA, tolerance: Int = 24) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance
            && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
    }

    var isNearWhite: Bool { red > 200 && green > 200 && blue > 200 }
    var isNearBlack: Bool { red < 40 && green < 40 && blue < 40 }
}

/// A captured bitmap read pixel by pixel. Lives only inside the closure it was handed to.
struct PixelSampler {
    /// Pixel dimensions.
    let width: Int
    let height: Int
    /// Pixels per point of the capture.
    let scale: CGFloat
    private let samples: [UInt8]

    fileprivate init(_ image: UIImage) throws {
        let cgImage = try #require(image.cgImage, "the capture had no CGImage")
        width = cgImage.width
        height = cgImage.height
        scale = image.scale

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

    /// Point dimensions.
    var size: CGSize { CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }

    /// The pixel at integer pixel coordinates. Out of range reads as transparent black.
    func pixel(x: Int, y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else {
            return RGBA(red: 0, green: 0, blue: 0, alpha: 0)
        }
        let offset = (y * width + x) * 4
        return RGBA(
            red: samples[offset],
            green: samples[offset + 1],
            blue: samples[offset + 2],
            alpha: samples[offset + 3]
        )
    }

    /// The pixel under `point`, in points.
    func color(at point: CGPoint) -> RGBA {
        pixel(x: Int((point.x * scale).rounded(.down)), y: Int((point.y * scale).rounded(.down)))
    }

    /// Every pixel inside `rect`, in points, row by row.
    func pixels(in rect: CGRect) -> [RGBA] {
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !pixelRect.isNull, !pixelRect.isEmpty else { return [] }
        var found: [RGBA] = []
        found.reserveCapacity(Int(pixelRect.width * pixelRect.height))
        for y in Int(pixelRect.minY)..<Int(pixelRect.maxY) {
            for x in Int(pixelRect.minX)..<Int(pixelRect.maxX) {
                found.append(pixel(x: x, y: y))
            }
        }
        return found
    }

    /// How many pixels inside `rect`, in points, satisfy `predicate`.
    func count(in rect: CGRect, where predicate: (RGBA) -> Bool) -> Int {
        pixels(in: rect).reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }

    /// The largest and smallest luma in `rect`, in points; the whole bitmap when nil.
    func luminanceRange(in rect: CGRect? = nil) -> ClosedRange<Double> {
        let region = rect ?? CGRect(origin: .zero, size: size)
        var low = Double.infinity
        var high = -Double.infinity
        for pixel in pixels(in: region) {
            let luma = pixel.luminance
            low = min(low, luma)
            high = max(high, luma)
        }
        return low <= high ? low...high : 0...0
    }

    /// Whether `rect` (points) holds glyph-like ink: pixels whose luma differs from the region's
    /// median by more than `contrast`, making up more than `fraction` of the region. A painted
    /// label has them; a control whose text was pushed off screen, clipped away, or drawn behind
    /// something opaque is a flat fill. Regions too small to hold a glyph count as painted.
    ///
    /// The region is the frame less what a control paints that is not its text: a hairline
    /// border (5 pt off each side) and the arcs of its rounded corners, which intrude along the
    /// top and bottom edges only (a quarter of the height off each). A flat lime capsule with its
    /// text clipped away read as inked on its corners alone until those were excluded - and a 15%
    /// inset on every side, the first cut at that, discarded exactly the pixels a short left-aligned
    /// label lives in: "Male" and "Other" in a 336 pt option row were flat fills, "Female" and
    /// "Prefer not to say" spilled past the margin and passed. `contrast` sits low enough for
    /// dimmed copy - a disabled control's label at a third of full opacity - and far above the
    /// noise of a flat fill.
    func hasInk(in rect: CGRect, contrast: Double = 20, fraction: Double = 0.005) -> Bool {
        guard let region = Self.inkRegion(of: rect, in: size) else { return true }
        let lumas = pixels(in: region).map(\.luminance)
        guard lumas.count >= 16 else { return true }
        let median = Self.median(of: lumas)
        let inked = lumas.reduce(0) { abs($1 - median) > contrast ? $0 + 1 : $0 }
        return Double(inked) / Double(lumas.count) > fraction
    }

    /// The upper median of `values` - the element a full sort would put at `count / 2` - found
    /// by quickselect in linear expected time. The three-way partition keeps a region that is
    /// one flat colour, the common case, linear too: a two-way partition degrades to quadratic
    /// when every value is equal.
    static func median(of values: [Double]) -> Double {
        precondition(!values.isEmpty)
        var values = values
        let target = values.count / 2
        var low = 0
        var high = values.count - 1
        while low < high {
            let pivot = values[(low + high) / 2]
            var below = low
            var cursor = low
            var above = high
            while cursor <= above {
                let value = values[cursor]
                if value < pivot {
                    values.swapAt(below, cursor)
                    below += 1
                    cursor += 1
                } else if value > pivot {
                    values.swapAt(cursor, above)
                    above -= 1
                } else {
                    cursor += 1
                }
            }
            if target < below {
                high = below - 1
            } else if target > above {
                low = above + 1
            } else {
                return pivot
            }
        }
        return values[target]
    }

    /// The part of `rect` (points) `hasInk` reads, or nil when the frame is too small to judge.
    static func inkRegion(of rect: CGRect, in size: CGSize) -> CGRect? {
        let onScreen = rect.intersection(CGRect(origin: .zero, size: size))
        guard !onScreen.isNull, onScreen.width >= 14, onScreen.height >= 8 else { return nil }
        let region = onScreen.insetBy(dx: 5, dy: onScreen.height * 0.25)
        guard region.width >= 4, region.height >= 2 else { return nil }
        return region
    }

    /// What `hasInk` saw in `rect`, for a diagnostic line.
    func inkReport(in rect: CGRect, contrast: Double = 20) -> String {
        guard let region = Self.inkRegion(of: rect, in: size) else { return "too-small-or-off-screen" }
        let lumas = pixels(in: region).map(\.luminance)
        guard !lumas.isEmpty else { return "empty-region" }
        let median = Self.median(of: lumas)
        let inked = lumas.reduce(0) { abs($1 - median) > contrast ? $0 + 1 : $0 }
        return "region=\(region.integral) median=\(Int(median)) range=\(Int(lumas.min()!))...\(Int(lumas.max()!)) ink=\(inked)/\(lumas.count)"
    }

    /// The pixel bounds of everything in `rect` (points) satisfying `predicate`, in points, or
    /// nil when nothing does.
    func bounds(in rect: CGRect? = nil, where predicate: (RGBA) -> Bool) -> CGRect? {
        let region = rect ?? CGRect(origin: .zero, size: size)
        let pixelRect = CGRect(
            x: region.minX * scale,
            y: region.minY * scale,
            width: region.width * scale,
            height: region.height * scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !pixelRect.isNull, !pixelRect.isEmpty else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in Int(pixelRect.minY)..<Int(pixelRect.maxY) {
            for x in Int(pixelRect.minX)..<Int(pixelRect.maxX) where predicate(pixel(x: x, y: y)) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }
}
