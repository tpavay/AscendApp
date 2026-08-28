//
//  TelemetryManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/16/25.
//

import Foundation
import os.lock

/// Thread-safe telemetry manager for shared app events and error reporting.
/// Call `configure()` once at app launch, after Firebase is configured.
final class TelemetryManager: @unchecked Sendable {
    static let shared = TelemetryManager()

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let sinks: [any TelemetrySink]
    private let crashlyticsReporter: any CrashlyticsReporting
    private let collectionEnabledOverride: Bool?
    private let buildMetadata: TelemetryBuildMetadata
    private let envelope: TelemetryEnvelope
    private let identityStore: any TelemetryIdentityStoring

    var isCollectionEnabled: Bool {
        lock.withLock(\.isCollectionEnabled)
    }

    init(
        sinks: [any TelemetrySink]? = nil,
        crashlyticsReporter: (any CrashlyticsReporting)? = nil,
        collectionEnabledOverride: Bool? = nil,
        buildMetadata: TelemetryBuildMetadata = .current,
        identityStore: any TelemetryIdentityStoring = TelemetryIdentityStore.live
    ) {
        let reporter = crashlyticsReporter ?? CompositeCrashlyticsReporter(
            reporters: [
                FirebaseCrashlyticsReporter(),
                SentryDiagnosticsReporter()
            ]
        )
        self.crashlyticsReporter = reporter
        self.collectionEnabledOverride = collectionEnabledOverride
        self.buildMetadata = buildMetadata
        self.envelope = TelemetryEnvelope(resolving: buildMetadata)
        self.identityStore = identityStore
        if let sinks {
            self.sinks = sinks
        } else {
            var defaultSinks: [any TelemetrySink] = [
                FirebaseTelemetrySink(),
                MixpanelTelemetrySink(buildMetadata: buildMetadata),
                CrashlyticsBreadcrumbSink(reporter: reporter)
            ]

            #if DEBUG
            defaultSinks.append(
                DebugTelemetryConsoleSink {
                    DebugTelemetryConsoleStore.shared
                }
            )
            #endif

            self.sinks = defaultSinks
        }
    }

    // MARK: - Collection Gating

    /// Call once at app launch, after FirebaseApp.configure(). Safe to call multiple times.
    func configure() {
        // Read before the lock: the identity the last launch left behind is what tells a genuine
        // sign-out apart from a cold launch that merely has no session.
        let restoredUserID = identityStore.identifiedUserID
        let shouldConfigure = lock.withLock { state -> Bool in
            guard !state.didConfigure else { return false }
            state.didConfigure = true
            state.identifiedUserID = restoredUserID
            return true
        }

        guard shouldConfigure else { return }

        let enabled = collectionEnabledOverride ?? Self.shouldEnableCollection(
            buildMetadata: buildMetadata
        )
        lock.withLock { $0.isCollectionEnabled = enabled }

        crashlyticsReporter.setCollectionEnabled(enabled)
        sinks.forEach { $0.setCollectionEnabled(enabled) }
    }

    static func shouldEnableCollection(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard,
        buildMetadata: TelemetryBuildMetadata = .current,
        runtime: TelemetryRuntimeEnvironment = .current
    ) -> Bool {
        // The unit-test host must never ship telemetry: test-injected failures
        // would surface in Crashlytics/Sentry as real issues. This overrides
        // every other enablement path, including persisted debug toggles.
        if environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil {
            return false
        }

        // A production build running on a simulator is a rehearsal wearing a customer's clothes:
        // the envelope, the token, and the Firebase plist are all the shipped ones, and nothing in
        // the payload separates it afterwards. It is deliberately above the launch-argument
        // overrides so no flag can re-open it - production is measured, never rehearsed.
        if buildMetadata.appEnvironment == "production", runtime.isSimulator {
            return false
        }

        if arguments.contains("-TelemetryDisabled") {
            #if DEBUG
            userDefaults.set(false, forKey: debugCollectionEnabledDefaultsKey)
            #endif
            return false
        }

        if arguments.contains("-TelemetryEnabled") {
            #if DEBUG
            userDefaults.set(true, forKey: debugCollectionEnabledDefaultsKey)
            #endif
            return true
        }

        #if DEBUG
        if let environmentValue = environment["ASC_DEBUG_TELEMETRY_ENABLED"],
           let enabled = debugBooleanValue(environmentValue) {
            userDefaults.set(enabled, forKey: debugCollectionEnabledDefaultsKey)
            return enabled
        }

        if userDefaults.object(forKey: debugCollectionEnabledDefaultsKey) != nil {
            return userDefaults.bool(forKey: debugCollectionEnabledDefaultsKey)
        }

        return false
        #else
        return true
        #endif
    }

    #if DEBUG
    private static let debugCollectionEnabledDefaultsKey = "debug.telemetry.collectionEnabled"

    private static func debugBooleanValue(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    func debugEnableCollectionForSession() {
        lock.withLock { $0.isCollectionEnabled = true }
        crashlyticsReporter.setCollectionEnabled(true)
        sinks.forEach { $0.setCollectionEnabled(true) }
        setAppMetadata()
    }
    #endif

    // MARK: - User Identity

    func setUserId(_ userId: String) {
        guard isCollectionEnabled else { return }

        let previousUserID = lock.withLock { state -> String? in
            let previous = state.identifiedUserID
            state.identifiedUserID = userId
            return previous
        }

        // Mixpanel links whatever anonymous id is in play to whoever identifies next, so
        // identifying a second account over a live one merges two climbers into one profile.
        // Clearing first is what keeps an account switch two people.
        if let previousUserID, previousUserID != userId {
            forwardClearedIdentity()
        }

        identityStore.store(userId)
        crashlyticsReporter.setUserID(userId)
        sinks.forEach { $0.setUserID(userId) }
    }

    /// Clears the identity only when there is one to clear, and reports whether it did.
    ///
    /// Firebase's auth listener reports "no user" on every signed-out cold launch, not only on a
    /// sign-out, and clearing there is pure loss: `MixpanelInstance.reset()` rotates the anonymous
    /// device id, so `app_first_opened` and every pre-auth onboarding event end up on a Mixpanel
    /// user that never acts again. See `TelemetryIdentityStore`.
    ///
    /// The return value is what lets a caller tell the two apart - it is the app's only answer to
    /// "did somebody actually sign out", so anything else reporting a sign-out hangs off it.
    @discardableResult
    func clearUserId() -> Bool {
        guard isCollectionEnabled else { return false }

        let hadIdentity = lock.withLock { state -> Bool in
            guard state.identifiedUserID != nil else { return false }
            state.identifiedUserID = nil
            return true
        }

        guard hadIdentity else { return false }

        identityStore.clear()
        forwardClearedIdentity()
        return true
    }

    private func forwardClearedIdentity() {
        crashlyticsReporter.setUserID(nil)
        sinks.forEach { $0.setUserID(nil) }
    }

    func setUserProperty(_ name: String, value: String?) {
        guard isCollectionEnabled else { return }
        sinks
            .filter { $0.supportedDestinations.contains(.analytics) }
            .forEach { $0.setUserProperty(name, value: value) }
    }

    // MARK: - Event Tracking

    func track(_ event: any TelemetryEvent) {
        track(event.record)
    }

    func track(_ record: TelemetryRecord) {
        guard isCollectionEnabled else { return }

        let envelopedRecord = EnvelopedTelemetryRecord(record: record, envelope: envelope)
        sinks
            .filter { $0.supportedDestinations.isDisjoint(with: envelopedRecord.destinations) == false }
            .forEach { $0.record(envelopedRecord) }
    }

    func track(screen: TelemetryScreen) {
        guard isCollectionEnabled else { return }

        let envelopedScreen = EnvelopedTelemetryScreen(screen: screen, envelope: envelope)
        sinks
            .filter { $0.supportedDestinations.contains(.analytics) }
            .forEach { $0.record(screen: envelopedScreen) }
    }

    // MARK: - Custom Keys (Native Types)

    enum Key: String {
        case hasAppAccess = "has_app_access"
        /// The two halves the discarded `activeInCurrentEnvironment` filter compared (#506).
        /// Diagnostic only - nothing decides access from either.
        case holdsSandboxEntitlement = "holds_sandbox_entitlement"
        case storeKitReceiptName = "storekit_receipt_name"
        case appEnvironment = "app_environment"
        case buildConfig = "build_config"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case lastDiagnosticEvent = "last_diagnostic_event"
    }

    func set(_ key: Key, value: Bool) {
        guard isCollectionEnabled else { return }
        crashlyticsReporter.setCustomValue(value, forKey: key.rawValue)
    }

    func set(_ key: Key, value: Int) {
        guard isCollectionEnabled else { return }
        crashlyticsReporter.setCustomValue(value, forKey: key.rawValue)
    }

    func set(_ key: Key, value: String) {
        guard isCollectionEnabled else { return }
        crashlyticsReporter.setCustomValue(value, forKey: key.rawValue)
    }

    func setAppMetadata() {
        guard isCollectionEnabled else { return }
        set(.appEnvironment, value: envelope.appEnvironment)
        set(.buildConfig, value: envelope.buildConfig)
        set(.appVersion, value: envelope.appVersion)
        set(.buildNumber, value: envelope.buildNumber)
    }

    // MARK: - Breadcrumbs (Structured Tokens)

    enum Breadcrumb: String {
        case authSessionRestored = "auth:session_restored"
        case authInteractiveSignInSuccess = "auth:interactive_sign_in_success"
        case authSignInFailed = "auth:sign_in_failed"
        case authSignOut = "auth:sign_out"
        case authProfileLoaded = "auth:profile_loaded"

        var record: TelemetryRecord {
            TelemetryRecord(
                name: rawValue,
                destinations: [.crashlytics]
            )
        }
    }

    func log(_ breadcrumb: Breadcrumb) {
        track(breadcrumb.record)
    }

    // MARK: - Non-Fatal Errors (Normalized)

    enum ErrorContext: String {
        case auth
        case firestore
        case storage
        case healthKit
        case network
    }

    /// Records a non-fatal error.
    /// - additionalInfo uses [String: String] to prevent PII leakage
    /// - Keep key set small/stable; avoid raw error messages
    func recordError(
        _ error: Error,
        context: ErrorContext,
        code: String,
        additionalInfo: [String: String]? = nil
    ) {
        guard isCollectionEnabled else { return }
        crashlyticsReporter.record(
            error: error,
            context: context.rawValue,
            code: code,
            additionalInfo: additionalInfo
        )
    }
}

private extension TelemetryManager {
    struct State {
        var isCollectionEnabled = false
        var didConfigure = false
        /// Mirrors `TelemetryIdentityStore` so the transition is decided under the lock rather
        /// than against a value another thread may already have moved.
        var identifiedUserID: String?
    }
}
