import Foundation
import SwiftUI
import Testing
import UIKit
@preconcurrency import Sentry
@testable import AscendApp

/// Runs the real SDK against a climber's screen and reads the bytes it would
/// have put on the wire.
///
/// `SentryDiagnosticsConfigurationTests` asserts that `beforeCaptureScreenshot`
/// and `beforeCaptureViewHierarchy` answer no for an ordinary error; this suite
/// is the end of that claim rather than its middle. It starts Sentry with the
/// production options `SentryOptionsFactory` builds, points the DSN at a
/// refused local port so the envelopes stay cached on disk instead of leaving
/// the device, captures the two events that matter through the same SDK entry
/// points `SentryDiagnosticsReporter` uses, and opens the resulting envelopes.
///
/// - An ordinary handled error - the shape all 22 `recordError` call sites
///   produce - must carry no attachment at all, because producing one renders
///   the live UI synchronously on the main thread.
/// - A severe event must still carry the view tree, so the gate cannot be read
///   as "screen captures were quietly turned off". The tree is the attachment
///   that answers only to the policy, so it carries that claim on every host.
/// - The picture needs one thing more than the policy's yes: a window the SDK
///   found to photograph. That is a property of the machine running the test,
///   not of Ascend's capture policy - a simulator booted headless under CI does
///   not reliably keep the host foreground-active, and `SentryApplication`
///   takes a scene-delegate window only from a `.foregroundActive` scene. So
///   the picture is asserted present or absent accordingly - never skipped.
///
/// **The window count is read out of the SDK's own view tree, not out of a
/// second reading of `UIApplication`.** Both attachments are built from one
/// `getWindows()` call: `SentryScreenshotSource.appScreenshots()` returns
/// nothing for an empty list, while `SentryViewHierarchyProviderHelper`
/// serialises that same empty list into valid JSON and attaches it anyway. The
/// tree therefore reports what the SDK actually had in hand, and keying the
/// picture on it means this suite cannot disagree with the SDK by
/// re-implementing a query the SDK is free to change. `hostDescription` still
/// reads the host directly, but only to say so in the record.
///
/// The severe event's own `screenshot.png` is written out where the host
/// produced one, so what a triager would open in Sentry can be looked at
/// directly: a climber's heart-rate trace and account identity, painted out.
/// Either way the run log carries one line naming the host, the windows the SDK
/// found, and the attachments that left - so which half of the rule a given run
/// proved is in the record rather than inferred from a green tick.
///
/// Artifacts land in `ASCEND_EVIDENCE_DIR` when it is set, and in the test
/// host's temporary directory otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct SentryCrashContextEnvelopeEvidenceTests {
    /// A DSN whose host refuses the connection immediately, so nothing this
    /// suite captures can reach a Sentry project and every envelope stays where
    /// it can be read: the transport stores an envelope before sending it, and
    /// keeps it when the response is nil.
    private static let refusedDSN = "https://evidencekey@127.0.0.1:1/1"

    @Test
    func anOrdinaryErrorShipsNoScreenCaptureWhileASevereOneStillCarriesAMaskedOne() async throws {
        let cache = try Self.makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let options = try #require(Self.productionOptions(), "the factory declined to build production options")
        options.cacheDirectoryPath = cache.path()

        let window = try #require(Self.appWindow(), "the test host has no scene-delegate window to photograph")
        let originalRoot = window.rootViewController
        defer { window.rootViewController = originalRoot }
        try await Self.showClimbersScreen(in: window)

        SentrySDK.start(options: options)
        defer { SentrySDK.close() }

        // The shape `SentryDiagnosticsReporter.record(error:context:code:)` puts
        // on the wire, captured through the same SDK call it makes.
        let handled = SentrySDK.capture(error: Self.recordedError()) { scope in
            scope.setTag(value: "workout_sync", key: "ascend_error_context")
            scope.setTag(value: "workout_upload_failed", key: "ascend_error_code")
        }
        let handledEnvelope = try await Self.envelope(for: handled, in: cache)

        let severe = SentrySDK.capture(event: Self.unhandledEvent())
        let severeEnvelope = try await Self.envelope(for: severe, in: cache)

        #expect(
            handledEnvelope.attachments.isEmpty,
            """
            an ordinary handled error shipped \(handledEnvelope.attachmentNames), so every \
            `recordError` call site is paying for a synchronous main-thread render again.
            """
        )

        // The view tree answers to the capture policy alone - the SDK writes one
        // whether or not it was handed a window - so it carries the "a severe
        // event still gets its context" half of the rule on every host.
        let tree = try #require(
            severeEnvelope.attachments.first { $0.filename == "view-hierarchy.json" }?.payload,
            "a severe event shipped no view hierarchy: \(severeEnvelope.attachmentNames)"
        )
        let hierarchy = String(decoding: tree, as: UTF8.self)

        // What the SDK actually had to capture, in its own words.
        let windowsTheSDKFound = try #require(
            Self.windowCount(in: tree),
            "the view hierarchy names no window list, so what the SDK captured cannot be read"
        )

        // One line per run, whichever half it proves, so the record never has to
        // be reconstructed from a stack trace the way this branch's was.
        print(
            """
            sentry crash context: host \(Self.hostDescription); SDK found \(windowsTheSDKFound) window(s); \
            ordinary [\(handledEnvelope.attachmentNames.joined(separator: ", "))]; \
            severe [\(severeEnvelope.attachmentNames.joined(separator: ", "))]
            """
        )

        guard windowsTheSDKFound > 0 else {
            // Nothing to photograph is not the policy declining: the picture is
            // the one attachment `SentryScreenshotSource` drops when the window
            // list is empty, while the tree above still ships. Assert that
            // shape rather than skipping, so this branch cannot become a hole.
            #expect(
                !severeEnvelope.attachmentNames.contains("screenshot.png"),
                """
                the SDK shipped a picture of a window list it reported as empty (\(Self.hostDescription)): \
                \(severeEnvelope.attachmentNames)
                """
            )
            try Self.writeArtifacts(handled: handledEnvelope, severe: severeEnvelope, photographedHost: false)
            return
        }

        // The SDK had the climber's window in hand, so every claim below is the
        // unconditional one: a severe event's picture, of that window, of the
        // masked screen.
        #expect(
            severeEnvelope.attachmentNames.contains("screenshot.png"),
            """
            a severe event shipped no screenshot though the SDK captured \(windowsTheSDKFound) window(s) \
            (\(Self.hostDescription)): \(severeEnvelope.attachmentNames)
            """
        )

        // The attachments are of the screen that was up, not of an empty window
        // a later change could leave behind: the picture is the window's own
        // size, and the tree names the mask marker the chart carries.
        let screenshot = try #require(
            severeEnvelope.attachments.first { $0.filename == "screenshot.png" }.flatMap { UIImage(data: $0.payload) },
            "the screenshot attachment is not a readable PNG"
        )
        #expect(screenshot.size == window.bounds.size, "the screenshot is not of the window that was up")

        #expect(
            hierarchy.contains("SentryMaskedRegionView"),
            "the captured tree carries no mask marker, so the screenshot is not of the masked climber screen"
        )

        try Self.writeArtifacts(handled: handledEnvelope, severe: severeEnvelope, photographedHost: true)
    }

    // MARK: - The climber's screen

    /// The window the SDK photographs, which is the one the scene delegate owns
    /// rather than any window a test brings up: `SentryApplication.getWindows`
    /// reads `UIWindowSceneDelegate.window`, so a screenshot only ever shows
    /// what is in that one.
    private static func appWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { ($0.delegate as? UIWindowSceneDelegate)?.window ?? nil }
            .first
    }

    /// How many windows the SDK had in hand when it built these attachments,
    /// read off the tree it wrote rather than asked of `UIApplication` a second
    /// time.
    ///
    /// `SentryViewHierarchyProviderHelper` serialises the list `getWindows()`
    /// returned under a top-level `windows` key, and does so even when that list
    /// is empty - which is exactly the case that separates the two attachments.
    /// `nil` means the tree is not the shape this suite knows how to read, which
    /// is a failure rather than an empty host.
    private static func windowCount(in tree: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: tree) as? [String: Any],
              let windows = root["windows"] as? [Any]
        else { return nil }

        return windows.count
    }

    /// The host state the record and both screenshot expectations name, so a
    /// future failure says which side of the precondition it landed on instead
    /// of only that an attachment was missing.
    private static var hostDescription: String {
        let scenes = UIApplication.shared.connectedScenes.map { scene in
            "\(type(of: scene)) \(name(of: scene.activationState))"
        }
        let bounds = appWindow().map { "\($0.bounds.size)" } ?? "no scene-delegate window"
        return "window \(bounds); scenes [\(scenes.joined(separator: ", "))]"
    }

    private static func name(of state: UIScene.ActivationState) -> String {
        switch state {
        case .foregroundActive: "foregroundActive"
        case .foregroundInactive: "foregroundInactive"
        case .background: "background"
        case .unattached: "unattached"
        @unknown default: "activation=\(state.rawValue)"
        }
    }

    /// Real Ascend surfaces, so the screenshot the SDK takes is the one a crash
    /// would have taken: a masked heart-rate chart above the account identity
    /// the SDK's own text masking covers.
    private static func showClimbersScreen(in window: UIWindow) async throws {
        let start = Date(timeIntervalSince1970: 1_750_300_000)
        let samples = (0..<600).map { second in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(TimeInterval(second) * 3),
                heartRate: 100 + Int((sin(Double(second) / 37) * 40).rounded())
            )
        }

        let screen = VStack(alignment: .leading, spacing: 16) {
            HeartRateChartView(
                heartRateData: samples,
                workoutStartTime: start,
                workoutDuration: 1_800,
                averageHeartRateBpm: 140,
                maxHeartRateBpm: 180
            )

            Text("Alexandra Featherstone")
                .font(.title2)
            Text("alexandra@example.com")
                .font(.body)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)

        let controller = UIHostingController(rootView: screen)
        controller.overrideUserInterfaceStyle = .dark

        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // A turn of the run loop so SwiftUI has committed its hosting views and
        // layers before the SDK walks the hierarchy for redaction regions.
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
    }

    // MARK: - The two events

    private static func recordedError() -> Error {
        NSError(
            domain: "AscendApp.WorkoutSync",
            code: 17,
            userInfo: [NSLocalizedDescriptionKey: "The climb could not be uploaded."]
        )
    }

    /// An unhandled exception: severe by the same rule the flood guard uses, and
    /// the one severe shape that actually reaches the callbacks - a crash's own
    /// picture is written by the crash handler, and `SentryScreenshotIntegration`
    /// returns before consulting the policy for any event flagged fatal.
    private static func unhandledEvent() -> Event {
        let event = Event(level: .error)
        let exception = Exception(value: "unrecognized selector", type: "NSInvalidArgumentException")
        let mechanism = Mechanism(type: "generic")
        mechanism.handled = false
        exception.mechanism = mechanism
        event.exceptions = [exception]
        return event
    }

    private static func productionOptions() -> Options? {
        SentryOptionsFactory.makeOptions(
            configuration: SentryConfiguration(infoDictionary: [SentryConfiguration.dsnInfoKey: refusedDSN]),
            buildMetadata: TelemetryBuildMetadata(
                appEnvironment: "production",
                buildConfig: "Release",
                appVersion: "1.0.0",
                buildNumber: "42",
                bundleIdentifier: "com.ascend.app"
            ),
            floodGuard: SentryEventFloodGuard()
        )
    }

    // MARK: - Reading what the SDK wrote

    private struct StoredEnvelope {
        let eventID: String
        let items: [Item]

        var attachments: [Item] { items.filter { $0.type == "attachment" } }
        var attachmentNames: [String] { attachments.map { $0.filename ?? "unnamed" } }
        var itemSummary: String {
            items.map { item in
                let name = item.filename.map { " \($0)" } ?? ""
                return "\(item.type)\(name) (\(item.payload.count) bytes)"
            }
            .joined(separator: ", ")
        }

        struct Item {
            let type: String
            let filename: String?
            let payload: Data
        }
    }

    /// Waits for the envelope the SDK stored for `id` and parses it.
    ///
    /// The transport writes an envelope to disk before it tries to send it, so
    /// this is what would have left the device byte for byte - not a
    /// reconstruction of it.
    private static func envelope(for id: SentryId, in cache: URL) async throws -> StoredEnvelope {
        SentrySDK.flush(timeout: 5)

        for _ in 0..<100 {
            if let match = storedEnvelopes(in: cache).first(where: { $0.eventID == id.sentryIdString }) {
                return match
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        Issue.record("the SDK never stored an envelope for \(id.sentryIdString)")
        throw CancellationError()
    }

    private static func storedEnvelopes(in cache: URL) -> [StoredEnvelope] {
        let files = FileManager.default
            .enumerator(at: cache, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.deletingLastPathComponent().lastPathComponent == "envelopes" }
            ?? []

        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return parse(data)
        }
    }

    /// Parses the envelope wire format: a header line, then each item as a
    /// header line followed by exactly `length` bytes of payload.
    private static func parse(_ data: Data) -> StoredEnvelope? {
        var cursor = data.startIndex

        func readLine() -> Data? {
            guard cursor < data.endIndex else { return nil }
            guard let newline = data[cursor...].firstIndex(of: 0x0A) else {
                let line = data[cursor...]
                cursor = data.endIndex
                return Data(line)
            }
            let line = data[cursor..<newline]
            cursor = data.index(after: newline)
            return Data(line)
        }

        guard let headerLine = readLine(),
              let header = try? JSONSerialization.jsonObject(with: headerLine) as? [String: Any],
              let eventID = header["event_id"] as? String
        else { return nil }

        var items: [StoredEnvelope.Item] = []

        while let itemHeaderLine = readLine(), !itemHeaderLine.isEmpty {
            guard let itemHeader = try? JSONSerialization.jsonObject(with: itemHeaderLine) as? [String: Any],
                  let type = itemHeader["type"] as? String,
                  let length = itemHeader["length"] as? Int,
                  data.index(cursor, offsetBy: length, limitedBy: data.endIndex) != nil
            else { break }

            let end = data.index(cursor, offsetBy: length)
            items.append(
                StoredEnvelope.Item(
                    type: type,
                    filename: itemHeader["filename"] as? String,
                    payload: Data(data[cursor..<end])
                )
            )
            cursor = end
            if cursor < data.endIndex, data[cursor] == 0x0A {
                cursor = data.index(after: cursor)
            }
        }

        return StoredEnvelope(eventID: eventID, items: items)
    }

    // MARK: - Artifacts

    private static func makeCacheDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "sentry-crash-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeArtifacts(
        handled: StoredEnvelope,
        severe: StoredEnvelope,
        photographedHost: Bool
    ) throws {
        let directory = evidenceDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let picture = photographedHost
            ? """
              The severe event's screenshot.png and view-hierarchy.json are written beside this
              file. The picture is the SDK's own capture of the climber screen that was up - a
              heart-rate chart above an account name and email - masked by
              SentryOptionsFactory.makeScreenshotOptions, so the trace and every label are painted
              over before the PNG exists.
              """
            : """
              This host handed the SDK no window to photograph (\(hostDescription)), so the severe
              event carries its view hierarchy and no picture - the SDK drops the screenshot for an
              empty window list. The masked pixels themselves are proven by
              SentryMaskingEvidenceTests, which renders through the same shipped screenshot options.
              """

        let transcript = """
        Sentry crash context: what each event actually put on the wire
        ==============================================================

        Captured through the shipped production options (SentryOptionsFactory), read back
        out of the envelopes the SDK stored before sending.

        Ordinary handled error (SentryDiagnosticsReporter.record shape)
          event id: \(handled.eventID)
          envelope items: \(handled.itemSummary)
          attachments: \(handled.attachmentNames.isEmpty ? "none - no main-thread render was paid for" : handled.attachmentNames.joined(separator: ", "))

        Severe event (unhandled exception mechanism)
          event id: \(severe.eventID)
          envelope items: \(severe.itemSummary)
          attachments: \(severe.attachmentNames.joined(separator: ", "))

        \(picture)

        """

        try transcript.write(
            to: directory.appending(path: "sentry-crash-context-envelopes.txt"),
            atomically: true,
            encoding: .utf8
        )

        for attachment in severe.attachments {
            guard let filename = attachment.filename else { continue }
            try attachment.payload.write(to: directory.appending(path: "sentry-severe-event-\(filename)"))
        }

        print("crash context evidence: \(directory.path())")
    }

    private static var evidenceDirectory: URL {
        ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"].map { URL(filePath: $0) }
            ?? URL.temporaryDirectory.appending(path: "sentry-crash-context-evidence")
    }
}
