//
//  AscendApp.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import FirebaseCore
import GoogleSignIn
import SwiftUI
import SwiftData

@main
struct AscendApp: App {
    @UIApplicationDelegateAdaptor(AscendAppDelegate.self) private var appDelegate
    @State private var authVM: AuthenticationViewModel?
    private let modelContainer: ModelContainer?
    private let launchFailure: AppLaunchFailure?

    init() {
        let startupFailure = Self.configureFirebase() ?? Self.unreplacedMonetizationKeysFailure()
        let containerResult = Self.createModelContainer()

        switch containerResult {
        case .success(let modelContainer):
            self.modelContainer = modelContainer
            self.launchFailure = startupFailure
        case .failure(let failure):
            self.modelContainer = nil
            self.launchFailure = startupFailure ?? failure
        }

        if startupFailure == nil {
            #if DEBUG || STAGING
            SuperwallStaticConfigCacheBusterURLProtocol.register()
            #endif
            // Seeds the store synchronously from the SDK's persisted activation before anything
            // that touches data shape gets a chance to run, so the first pass of sync, restore,
            // and migrations sees whatever the backend last said even with no network.
            RemoteFeatureFlagService.shared.configure()
            PushNotificationService.shared.configure()
            TelemetryManager.shared.configure()
            TelemetryManager.shared.setAppMetadata()
            MonetizationManager.shared.configure()
            _authVM = State(initialValue: AuthenticationViewModel())
        } else {
            _authVM = State(initialValue: nil)
        }
    }

    private static func configureFirebase() -> AppLaunchFailure? {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            AppDiagnosticsRecorder.shared.record(
                "firebase_configuration_missing",
                level: .error,
                mirrorToCrashlytics: false
            )
            return .missingFirebaseConfiguration
        }
        FirebaseApp.configure()
        return nil
    }

    /// Backstop for the staging and production archive preflight
    /// (`scripts/ci/assert-monetization-keys-configured.mjs`): a shippable build
    /// whose monetization keys are still placeholders refuses to start instead of
    /// stranding every user behind a paywall that can never resolve.
    private static func unreplacedMonetizationKeysFailure() -> AppLaunchFailure? {
        #if DEBUG
        return nil
        #else
        guard MonetizationConfiguration.live.hasUnreplacedPlaceholderKeys else { return nil }

        AppDiagnosticsRecorder.shared.record(
            "monetization_placeholder_keys",
            level: .error,
            mirrorToCrashlytics: false
        )
        return .monetizationKeysNotReplaced
        #endif
    }

    var body: some Scene {
        WindowGroup {
            launchContent
                // Mixpanel's launch-time init breaks the catalog global accent
                // (NSAccentColorName), so set the accent explicitly at the root —
                // otherwise Color.accentColor resolves to system blue on some
                // staging and release surfaces.
                .tint(Color.ascendAccent)
                .accentColor(Color.ascendAccent)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url: url)
                }
        }
    }

    @ViewBuilder
    private var launchContent: some View {
        if let launchFailure {
            AppLaunchFailureView(failure: launchFailure)
        } else if let authVM, let modelContainer {
            RootNavigationHost(authVM: authVM)
                .environment(authVM)
                .environment(NetworkConnectivityService.shared)
                .environment(MonetizationManager.shared)
                .environment(MediaUploadManager.shared)
                .environment(ModerationStore.shared)
                .modelContainer(modelContainer)
        } else {
            AppLaunchFailureView(failure: .startupUnavailable)
        }
    }

    @MainActor
    private func handleDeepLink(url: URL) {
        // Let Google Sign-In handle its redirect URL
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }

        if LiveClimbActivityRouter.shared.route(from: url) {
            return
        }
    }
    
    private static func createModelContainer() -> ModelContainerCreationResult {
        do {
            let schema = AscendLocalStore.schema
            let config = ModelConfiguration(schema: schema)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AscendMigrationPlan.self,
                configurations: config
            )
            finishInterruptedMigrationIfNeeded(in: container)
            return .success(container)
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "model_container_creation_failed",
                level: .error,
                details: ["error_type": String(describing: type(of: error))],
                mirrorToCrashlytics: false
            )
            debugLog("Failed to create model container: \(error)")
            return .failure(.localDataUnavailable)
        }
    }

    /// A `didMigrate` that never landed leaves the store on V2 with the old workout sources gone,
    /// and SwiftData will not re-enter the stage to try again - so the retry has to live here, on
    /// the already-migrated store. It no-ops unless a previous launch left the stash behind.
    ///
    /// Failing to repair is not worth blocking launch over: the stash survives, so the next
    /// launch tries again.
    private static func finishInterruptedMigrationIfNeeded(in container: ModelContainer) {
        do {
            let report = try AscendMigrationPlan.recoverInterruptedMigrationIfNeeded(
                in: ModelContext(container)
            )

            // Abandonment reports itself from inside the plan, where the counts live and where a
            // test can hold the recorder.
            guard !report.abandonedAfterRepeatedFailures, report.repairedCount > 0 else { return }

            AppDiagnosticsRecorder.shared.record(
                "workout_source_migration_recovered",
                level: .warning,
                details: [
                    "repaired_count": String(report.repairedCount),
                    "workout_count": String(report.workoutCount),
                    "unresolved_count": String(report.unresolvedCount)
                ],
                mirrorToCrashlytics: true
            )
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "workout_source_migration_recovery_failed",
                level: .error,
                details: [
                    "error_type": String(describing: type(of: error)),
                    "error_description": String(describing: error)
                ],
                mirrorToCrashlytics: true
            )
            debugLog("Failed to finish interrupted workout source migration: \(error)")
        }
    }
}

private enum ModelContainerCreationResult {
    case success(ModelContainer)
    case failure(AppLaunchFailure)
}

private enum AppLaunchFailure {
    case missingFirebaseConfiguration
    case monetizationKeysNotReplaced
    case localDataUnavailable
    case startupUnavailable

    var title: String {
        switch self {
        case .missingFirebaseConfiguration:
            return "This build can't start."
        case .monetizationKeysNotReplaced:
            return "This build can't ship."
        case .localDataUnavailable:
            return "Ascend couldn't load your data."
        case .startupUnavailable:
            return "Ascend couldn't start."
        }
    }

    var message: String {
        switch self {
        case .missingFirebaseConfiguration:
            return "Install a fresh build of Ascend and try again."
        case .monetizationKeysNotReplaced:
            return "Its RevenueCat and Superwall keys are still placeholders. Replace them, then rebuild."
        case .localDataUnavailable:
            return "Restart the app. If this keeps happening, contact support before reinstalling."
        case .startupUnavailable:
            return "Restart the app and try again."
        }
    }
}

private struct AppLaunchFailureView: View {
    let failure: AppLaunchFailure

    var body: some View {
        VStack(spacing: 18) {
            Image("AppIconInternalAccent")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(failure.title)
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(failure.message)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct RootNavigationHost: View {
    let authVM: AuthenticationViewModel
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            RootView()
        }
        .id(authVM.user?.uid ?? "signedOut")
        .onChange(of: authVM.user?.uid) { _, _ in
            navigationPath = NavigationPath()
        }
    }
}
