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
    private let monetizationManager: MonetizationManager
    private let launchFailure: AppLaunchFailure?
    private let appStorage: UserDefaults
    #if DEBUG
    private let returningSubscriberJourneyConfiguration:
        ReturningSubscriberJourneyUITestScenario.Configuration?
    #endif

    init() {
        let startupFailure = Self.configureFirebase() ?? Self.unreplacedMonetizationKeysFailure()

        #if DEBUG
        if startupFailure == nil,
           let scenario = ReturningSubscriberJourneyUITestScenario.makeIfRequested() {
            modelContainer = scenario.modelContainer
            monetizationManager = scenario.monetizationManager
            launchFailure = nil
            appStorage = scenario.userDefaults
            returningSubscriberJourneyConfiguration = scenario
            _authVM = State(initialValue: scenario.authenticationViewModel)
            return
        }
        returningSubscriberJourneyConfiguration = nil
        #endif

        appStorage = .standard
        monetizationManager = .shared
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
            rootNavigationHost(authVM: authVM)
                .environment(authVM)
                .environment(NetworkConnectivityService.shared)
                .environment(monetizationManager)
                .environment(MediaUploadManager.shared)
                .modelContainer(modelContainer)
                .defaultAppStorage(appStorage)
        } else {
            AppLaunchFailureView(failure: .startupUnavailable)
        }
    }

    @ViewBuilder
    private func rootNavigationHost(authVM: AuthenticationViewModel) -> some View {
        #if DEBUG
        RootNavigationHost(
            authVM: authVM,
            returningSubscriberJourneyConfiguration: returningSubscriberJourneyConfiguration
        )
        #else
        RootNavigationHost(authVM: authVM)
        #endif
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
            return .success(try makeModelContainer())
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

    static func makeModelContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: Schema([
                Workout.self,
                WorkoutSourceLink.self,
                WorkoutParticipation.self,
                ActiveHeadphoneWorkoutDraft.self,
                LeaderboardStats.self,
                Routine.self,
                RoutineFolder.self,
                ClimbAttempt.self,
                PendingMediaUpload.self,
                PendingWorkoutDeletion.self,
                BestEffortCacheEntry.self,
                BestEffortCacheMetadata.self
            ]),
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, ActiveHeadphoneWorkoutDraft.self, LeaderboardStats.self, Routine.self, RoutineFolder.self, ClimbAttempt.self, PendingMediaUpload.self, PendingWorkoutDeletion.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self,
            configurations: config
        )
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
    #if DEBUG
    let returningSubscriberJourneyConfiguration:
        ReturningSubscriberJourneyUITestScenario.Configuration?
    #endif
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            #if DEBUG
            if let returningSubscriberJourneyConfiguration {
                RootView(
                    postAuthOnboardingCoordinator:
                        returningSubscriberJourneyConfiguration.postAuthOnboardingCoordinator,
                    lifecycleClient: .noOp
                )
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
        .id(authVM.authenticatedUserID ?? "signedOut")
        .onChange(of: authVM.authenticatedUserID) { _, _ in
            navigationPath = NavigationPath()
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if let returningSubscriberJourneyConfiguration {
                Text(returningSubscriberJourneyConfiguration.probe.paywallRegistrationCount.formatted())
                    .accessibilityLabel("Paywall registrations")
                    .accessibilityValue(
                        returningSubscriberJourneyConfiguration.probe.paywallRegistrationCount.formatted()
                    )
                    .accessibilityIdentifier(
                        "returningSubscriberJourney.paywallRegistrations"
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
            }
        }
        #endif
    }
}
