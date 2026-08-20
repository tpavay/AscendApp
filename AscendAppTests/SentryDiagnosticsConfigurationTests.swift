import Foundation
import Testing
@preconcurrency import Sentry
@testable import AscendApp

/// Pins what Ascend reports to Sentry and from where.
///
/// The project used to take events from all three environments and drowned in
/// them: over 30 days staging sent 791 and dev 533, against production's 23. Only
/// production reports now, and the dev case is proved against the live SDK
/// rather than by reading the source.
@Suite(.serialized)
struct SentryDiagnosticsConfigurationTests {
    private static let dsn = "https://examplePublicKey@o0.ingest.sentry.io/0"

    private static func configuration(dsn: String? = dsn) -> SentryConfiguration {
        SentryConfiguration(infoDictionary: dsn.map { [SentryConfiguration.dsnInfoKey: $0] } ?? [:])
    }

    private static func metadata(environment: String) -> TelemetryBuildMetadata {
        TelemetryBuildMetadata(
            appEnvironment: environment,
            buildConfig: environment,
            appVersion: "1.0.0",
            buildNumber: "42",
            bundleIdentifier: "com.ascend.app"
        )
    }

    private static func options(environment: String, dsn: String? = dsn) -> Options? {
        SentryOptionsFactory.makeOptions(
            configuration: configuration(dsn: dsn),
            buildMetadata: metadata(environment: environment),
            floodGuard: SentryEventFloodGuard()
        )
    }

    // MARK: - Where Sentry runs

    @Test(arguments: ["dev", "staging"])
    func noEnvironmentBelowProductionEvenBuildsOptions(environment: String) {
        #expect(Self.options(environment: environment) == nil)
    }

    @Test
    func productionBuildsOptionsWhenADSNIsPresent() throws {
        let options = try #require(Self.options(environment: "production"))

        #expect(options.environment == "production")
        #expect(options.dsn == Self.dsn)
        #expect(options.releaseName == "com.ascend.app@1.0.0+42")
    }

    @Test
    func aMissingDSNStillRefusesToStart() {
        #expect(Self.options(environment: "production", dsn: nil) == nil)
    }

    /// The acceptance criterion, proved against the live SDK: a dev build that
    /// enables collection does not initialise Sentry.
    ///
    /// `SentrySDK.isEnabled` is the SDK's own answer to "is a client running",
    /// so a passing assertion here is the absence of a client rather than the
    /// absence of a DSN.
    @Test
    func aDevBuildNeverInitialisesTheSDK() {
        #expect(!SentrySDK.isEnabled, "another suite left an SDK client running")

        let reporter = SentryDiagnosticsReporter(
            configuration: Self.configuration(),
            buildMetadata: Self.metadata(environment: "dev")
        )
        reporter.setCollectionEnabled(true)

        #expect(!SentrySDK.isEnabled)
    }

    // MARK: - Session replay

    /// Replay is deliberately not shipped, and both rates are asserted because
    /// either one above zero installs `SentrySessionReplayIntegration`, which
    /// renders and redacts the whole screen on the main thread once a second for
    /// the entire foreground session - on the same main thread whose stalls are
    /// production's most important signal.
    @Test
    func sessionReplayIsOffOnBothAxes() throws {
        let replay = try #require(Self.options(environment: "production")).sessionReplay

        #expect(replay.sessionSampleRate == 0)
        #expect(replay.onErrorSampleRate == 0)
    }

    // MARK: - Crash context

    @Test
    func aCrashCarriesAPictureAndAViewTree() throws {
        let options = try #require(Self.options(environment: "production"))

        #expect(options.attachScreenshot)
        #expect(options.attachViewHierarchy)
    }

    @Test
    func theCrashScreenshotPaintsOutEveryClassOfSensitiveContent() throws {
        let screenshot = try #require(Self.options(environment: "production")).screenshot

        #expect(screenshot.maskAllText)
        #expect(screenshot.maskAllImages)
        #expect(
            screenshot.maskedViewClasses.contains { $0 == SentryMaskedRegionView.self },
            """
            Swift Charts marks and AVPlayerLayer video are neither text nor images to the SDK, \
            so the app's own mask marker has to be registered - see SentryMaskingEvidenceTests.
            """
        )
    }

    /// The picture is not free: producing it renders the live UI synchronously
    /// on the main thread, and Ascend's 22 `recordError` call sites would each
    /// pay for one. Only a severe event does.
    @Test
    func anOrdinaryNonFatalErrorNeverPaysForAMainThreadRender() throws {
        let options = try #require(Self.options(environment: "production"))
        let beforeCaptureScreenshot = try #require(options.beforeCaptureScreenshot)
        let beforeCaptureViewHierarchy = try #require(options.beforeCaptureViewHierarchy)

        // The shape `SentryDiagnosticsReporter.record(error:...)` puts on the
        // wire: handled, error level, an ordinary domain.
        let recordedError = Self.noiseEvent()

        #expect(!beforeCaptureScreenshot(recordedError))
        #expect(!beforeCaptureViewHierarchy(recordedError))
    }

    /// The other half of the same rule, and the half that must never regress:
    /// the events worth diagnosing still carry their context.
    ///
    /// A crash's own screenshot never reaches this callback at all - the crash
    /// handler writes it, and `SentryScreenshotIntegration` returns early for
    /// any event flagged fatal - so this asserts the callback's answer for the
    /// severe events that *do* reach it, which is the only place it could say no.
    @Test
    func aSevereEventStillCarriesItsPictureAndViewTree() throws {
        let options = try #require(Self.options(environment: "production"))
        let beforeCaptureScreenshot = try #require(options.beforeCaptureScreenshot)
        let beforeCaptureViewHierarchy = try #require(options.beforeCaptureViewHierarchy)

        for event in [Event(level: .fatal), Self.appHangEvent(), Self.unhandledEvent()] {
            #expect(beforeCaptureScreenshot(event))
            #expect(beforeCaptureViewHierarchy(event))
        }
    }

    // MARK: - What stays off

    @Test
    func noneOfThePerformanceOrPiiSurfacesAreOn() throws {
        let options = try #require(Self.options(environment: "production"))

        #expect(!options.sendDefaultPii)
        #expect(options.tracesSampleRate == 0)
        #expect(!options.enableAutoPerformanceTracing)
        #expect(!options.enableUserInteractionTracing)
        #expect(!options.enableFileIOTracing)
    }

    // MARK: - The flood guard, as wired

    @Test
    func beforeSendDropsAFloodAndStampsWhatItDropped() throws {
        let floodGuard = SentryEventFloodGuard(
            limits: SentryEventFloodGuard.Limits(
                sessionCap: 100,
                perKeyCap: 2,
                perKeyWindow: 60,
                trackedKeyCap: 8
            )
        )
        let options = try #require(
            SentryOptionsFactory.makeOptions(
                configuration: Self.configuration(),
                buildMetadata: Self.metadata(environment: "production"),
                floodGuard: floodGuard
            )
        )
        let beforeSend = try #require(options.beforeSend)

        #expect(beforeSend(Self.noiseEvent()) != nil)
        #expect(beforeSend(Self.noiseEvent()) != nil)
        #expect(beforeSend(Self.noiseEvent()) == nil)

        // A guard that fires says so on the next event that gets through, rather
        // than quietly shrinking the project.
        let survivor = try #require(beforeSend(Self.noiseEvent(type: "OtherError")))
        #expect(survivor.tags?["ascend_flood_guard_dropped"] == "1")
    }

    @Test
    func beforeSendNeverDropsACrashOrAnAppHang() throws {
        let floodGuard = SentryEventFloodGuard(
            limits: SentryEventFloodGuard.Limits(
                sessionCap: 1,
                perKeyCap: 1,
                perKeyWindow: 60,
                trackedKeyCap: 1
            )
        )
        let options = try #require(
            SentryOptionsFactory.makeOptions(
                configuration: Self.configuration(),
                buildMetadata: Self.metadata(environment: "production"),
                floodGuard: floodGuard
            )
        )
        let beforeSend = try #require(options.beforeSend)

        // Spend every allowance the guard has.
        _ = beforeSend(Self.noiseEvent())
        #expect(beforeSend(Self.noiseEvent()) == nil)

        #expect(beforeSend(Event(level: .fatal)) != nil, "a crash was dropped by the noise guard")
        #expect(beforeSend(Self.appHangEvent()) != nil, "an app hang was dropped by the noise guard")
        #expect(beforeSend(Self.appHangEvent()) != nil)
    }

    private static func noiseEvent(type: String = "com.google.fcm") -> Event {
        let event = Event(level: .error)
        let exception = Exception(value: "Code: 505", type: type)
        let mechanism = Mechanism(type: "generic")
        mechanism.handled = true
        exception.mechanism = mechanism
        event.exceptions = [exception]
        return event
    }

    private static func unhandledEvent() -> Event {
        let event = Event(level: .error)
        let exception = Exception(value: "unrecognized selector", type: "NSInvalidArgumentException")
        let mechanism = Mechanism(type: "generic")
        mechanism.handled = false
        exception.mechanism = mechanism
        event.exceptions = [exception]
        return event
    }

    private static func appHangEvent() -> Event {
        let event = Event(level: .error)
        let exception = Exception(value: "App hanging for at least 2000 ms.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]
        return event
    }
}
