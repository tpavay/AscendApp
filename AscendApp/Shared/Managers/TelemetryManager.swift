//
//  TelemetryManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/16/25.
//

import FirebaseAnalytics
import FirebaseCrashlytics
import Foundation
import os.lock

/// Thread-safe telemetry manager for Crashlytics and Analytics.
/// Call `configure()` once at app launch from the main thread.
final class TelemetryManager: @unchecked Sendable {
    static let shared = TelemetryManager()

    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var isCollectionEnabled: Bool = false
        var didConfigure: Bool = false
    }

    var isCollectionEnabled: Bool {
        lock.withLock { $0.isCollectionEnabled }
    }

    private init() {}

    // MARK: - Collection Gating

    /// Call once at app launch, after FirebaseApp.configure(). Safe to call multiple times.
    func configure() {
        let shouldConfigure = lock.withLock { state -> Bool in
            guard !state.didConfigure else { return false }
            state.didConfigure = true
            return true
        }

        guard shouldConfigure else { return }

        let enabled = Self.shouldEnableCollection()
        lock.withLock { $0.isCollectionEnabled = enabled }

        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    private static func shouldEnableCollection() -> Bool {
        let args = ProcessInfo.processInfo.arguments

        // -TelemetryDisabled wins (force off even in Release/TestFlight)
        if args.contains("-TelemetryDisabled") {
            return false
        }

        // -TelemetryEnabled forces on (useful for testing in Debug)
        if args.contains("-TelemetryEnabled") {
            return true
        }

        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    // MARK: - User Identity

    func setUserId(_ userId: String) {
        guard isCollectionEnabled else { return }
        Crashlytics.crashlytics().setUserID(userId)
        Analytics.setUserID(userId)
    }

    func clearUserId() {
        guard isCollectionEnabled else { return }
        Crashlytics.crashlytics().setUserID("")
        Analytics.setUserID(nil)
    }

    // MARK: - Custom Keys (Native Types)

    enum Key: String {
        case isPremium = "is_premium"
        case stravaConnected = "strava_connected"
        case buildConfig = "build_config"
        case appVersion = "app_version"
        case buildNumber = "build_number"
    }

    func set(_ key: Key, value: Bool) {
        guard isCollectionEnabled else { return }
        Crashlytics.crashlytics().setCustomValue(value, forKey: key.rawValue)
    }

    func set(_ key: Key, value: Int) {
        guard isCollectionEnabled else { return }
        Crashlytics.crashlytics().setCustomValue(value, forKey: key.rawValue)
    }

    func set(_ key: Key, value: String) {
        guard isCollectionEnabled else { return }
        Crashlytics.crashlytics().setCustomValue(value, forKey: key.rawValue)
    }

    func setAppMetadata() {
        guard isCollectionEnabled else { return }
        let bundle = Bundle.main
        #if DEBUG
        set(.buildConfig, value: "debug")
        #else
        set(.buildConfig, value: "release")
        #endif
        set(.appVersion, value: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        set(.buildNumber, value: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
    }

    // MARK: - Breadcrumbs (Structured Tokens)

    enum Breadcrumb: String {
        // Auth
        case authSessionRestored = "auth:session_restored"
        case authInteractiveSignInSuccess = "auth:interactive_sign_in_success"
        case authSignInFailed = "auth:sign_in_failed"
        case authSignOut = "auth:sign_out"
        case authProfileLoaded = "auth:profile_loaded"

        // Strava
        case stravaConnectStarted = "strava:connect_started"
        case stravaConnectSuccess = "strava:connect_success"
        case stravaConnectFailed = "strava:connect_failed"
        case stravaSyncStarted = "strava:sync_started"
        case stravaSyncCompleted = "strava:sync_completed"
        case stravaSyncFailed = "strava:sync_failed"

        // Workouts
        case workoutImportStarted = "workout:import_started"
        case workoutImportCompleted = "workout:import_completed"
        case workoutImportFailed = "workout:import_failed"

        // Celebration
        case celebrationShown = "celebration:shown"
        case celebrationScreen1Completed = "celebration:screen1_completed"
        case celebrationScreen2Completed = "celebration:screen2_completed"
        case celebrationDismissed = "celebration:dismissed"
        case celebrationGoalCompleted = "celebration:goal_completed"
    }

    func log(_ breadcrumb: Breadcrumb) {
        guard isCollectionEnabled else { return }
        Crashlytics.crashlytics().log(breadcrumb.rawValue)
    }

    // MARK: - Non-Fatal Errors (Normalized)

    enum ErrorContext: String {
        case auth
        case strava
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

        var userInfo: [String: Any] = [
            "context": context.rawValue,
            "error_code": code
        ]

        if let additionalInfo {
            for (key, value) in additionalInfo {
                userInfo[key] = value
            }
        }

        Crashlytics.crashlytics().record(error: error, userInfo: userInfo)
    }
}
