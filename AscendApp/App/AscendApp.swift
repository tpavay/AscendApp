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
        let firebaseFailure = Self.configureFirebase()
        let containerResult = Self.createModelContainer()

        switch containerResult {
        case .success(let modelContainer):
            self.modelContainer = modelContainer
            self.launchFailure = firebaseFailure
        case .failure(let failure):
            self.modelContainer = nil
            self.launchFailure = firebaseFailure ?? failure
        }

        if firebaseFailure == nil {
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
            let config = ModelConfiguration(schema: Schema([
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
            ]))
            return .success(try ModelContainer(
                for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, ActiveHeadphoneWorkoutDraft.self, LeaderboardStats.self, Routine.self, RoutineFolder.self, ClimbAttempt.self, PendingMediaUpload.self, PendingWorkoutDeletion.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self,
                configurations: config
            ))
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
}

private enum ModelContainerCreationResult {
    case success(ModelContainer)
    case failure(AppLaunchFailure)
}

private enum AppLaunchFailure {
    case missingFirebaseConfiguration
    case localDataUnavailable
    case startupUnavailable

    var title: String {
        switch self {
        case .missingFirebaseConfiguration:
            return "This build can't start."
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
