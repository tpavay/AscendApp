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

    var isCollectionEnabled: Bool {
        lock.withLock(\.isCollectionEnabled)
    }

    init(
        sinks: [any TelemetrySink]? = nil,
        crashlyticsReporter: (any CrashlyticsReporting)? = nil,
        collectionEnabledOverride: Bool? = nil
    ) {
        let reporter = crashlyticsReporter ?? FirebaseCrashlyticsReporter()
        self.crashlyticsReporter = reporter
        self.collectionEnabledOverride = collectionEnabledOverride
        if let sinks {
            self.sinks = sinks
        } else {
            var defaultSinks: [any TelemetrySink] = [
                FirebaseTelemetrySink(),
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
        let shouldConfigure = lock.withLock { state -> Bool in
            guard !state.didConfigure else { return false }
            state.didConfigure = true
            return true
        }

        guard shouldConfigure else { return }

        let enabled = collectionEnabledOverride ?? Self.shouldEnableCollection()
        lock.withLock { $0.isCollectionEnabled = enabled }

        crashlyticsReporter.setCollectionEnabled(enabled)
        sinks.forEach { $0.setCollectionEnabled(enabled) }
    }

    private static func shouldEnableCollection() -> Bool {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-TelemetryDisabled") {
            return false
        }

        if args.contains("-TelemetryEnabled") {
            return true
        }

        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    private static var appEnvironmentName: String {
        #if DEBUG
        return "dev"
        #elseif STAGING
        return "staging"
        #else
        return "production"
        #endif
    }

    // MARK: - User Identity

    func setUserId(_ userId: String) {
        guard isCollectionEnabled else { return }
        crashlyticsReporter.setUserID(userId)
        sinks.forEach { $0.setUserID(userId) }
    }

    func clearUserId() {
        guard isCollectionEnabled else { return }
        crashlyticsReporter.setUserID(nil)
        sinks.forEach { $0.setUserID(nil) }
    }

    // MARK: - Event Tracking

    func track(_ event: any TelemetryEvent) {
        track(event.record)
    }

    func track(_ record: TelemetryRecord) {
        guard isCollectionEnabled else { return }

        let enrichedRecord = enrich(record)
        sinks
            .filter { !$0.supportedDestinations.isDisjoint(with: enrichedRecord.destinations) }
            .forEach { $0.record(enrichedRecord) }
    }

    func track(screen: TelemetryScreen) {
        guard isCollectionEnabled else { return }

        let enrichedScreen = enrich(screen)
        sinks
            .filter { $0.supportedDestinations.contains(.analytics) }
            .forEach { $0.record(screen: enrichedScreen) }
    }

    private func enrich(_ record: TelemetryRecord) -> TelemetryRecord {
        var parameters = record.parameters
        parameters["app_environment"] = .string(Self.appEnvironmentName)
        return TelemetryRecord(
            name: record.name,
            parameters: parameters,
            destinations: record.destinations
        )
    }

    private func enrich(_ screen: TelemetryScreen) -> TelemetryScreen {
        var parameters = screen.parameters
        parameters["app_environment"] = .string(Self.appEnvironmentName)
        return TelemetryScreen(
            name: screen.name,
            screenClass: screen.screenClass,
            parameters: parameters
        )
    }

    // MARK: - Custom Keys (Native Types)

    enum Key: String {
        case isPremium = "is_premium"
        case buildConfig = "build_config"
        case appVersion = "app_version"
        case buildNumber = "build_number"
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
        let bundle = Bundle.main
        #if DEBUG
        set(.buildConfig, value: "debug")
        #elseif STAGING
        set(.buildConfig, value: "staging")
        #else
        set(.buildConfig, value: "release")
        #endif
        set(.appVersion, value: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        set(.buildNumber, value: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
    }

    // MARK: - Breadcrumbs (Structured Tokens)

    enum Breadcrumb: String {
        case authSessionRestored = "auth:session_restored"
        case authInteractiveSignInSuccess = "auth:interactive_sign_in_success"
        case authSignInFailed = "auth:sign_in_failed"
        case authSignOut = "auth:sign_out"
        case authProfileLoaded = "auth:profile_loaded"
        case workoutImportStarted = "workout:import_started"
        case workoutImportCompleted = "workout:import_completed"
        case workoutImportFailed = "workout:import_failed"
        case celebrationShown = "celebration:shown"
        case celebrationScreen1Completed = "celebration:screen1_completed"
        case celebrationScreen2Completed = "celebration:screen2_completed"
        case celebrationDismissed = "celebration:dismissed"

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
    }
}
