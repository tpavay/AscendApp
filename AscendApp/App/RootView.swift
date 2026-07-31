//
//  RootView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(MonetizationManager.self) private var monetizationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(MediaUploadManager.self) private var uploadManager
    @Environment(ModerationStore.self) private var moderationStore
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var postAuthOnboardingCoordinator = PostAuthOnboardingCoordinator()
    @State private var tabRouter = TabRouter()
    @State private var accountDataConflict: AccountDataOwnershipConflict?
    @State private var profileCompletionCheckTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch rootRoute {
            case .signedOut:
                LandingScreen()
            case .signingIn:
                ProgressView("Signing In...")
                    .themedBackground()
            case .restoringSession:
                ProgressView("Restoring Session...")
                    .themedBackground()
            case .resolving:
                authenticatedContent(for: .resolving)
            case .onboarding:
                authenticatedContent(for: rootRoute)
            case .paywall:
                authenticatedContent(for: .paywall)
            case .mainApp:
                authenticatedContent(for: .mainApp)
            }
        }
        .environment(tabRouter)
        .animation(.easeInOut(duration: 0.25), value: rootRoute)
        .themeAware()
        .task {
            AppDiagnosticsRecorder.shared.record(
                "app_root_task_started",
                details: ["route": rootRoute.diagnosticName]
            )
            importCoordinator.configure(modelContext: modelContext)
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
            advancePostAuthOnboardingPastDisplayNameIfAvailable()
            await monetizationManager.refreshEntitlements()
            // Resume any pending uploads from previous session
            await uploadManager.processPendingUploads(modelContext: modelContext)
            await bootstrapAuthenticatedLocalState()
            await PushNotificationService.shared.synchronizeAuthenticatedDeviceIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            AppDiagnosticsRecorder.shared.record(
                "app_will_enter_foreground",
                details: ["route": rootRoute.diagnosticName]
            )
            // Retry pending uploads when app comes to foreground (network may have restored)
            Task {
                importCoordinator.configure(modelContext: modelContext)
                await monetizationManager.refreshEntitlements()
                await uploadManager.processPendingUploads(modelContext: modelContext)
                await bootstrapAuthenticatedLocalState()
                await PushNotificationService.shared.synchronizeAuthenticatedDeviceIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            AppDiagnosticsRecorder.shared.record(
                "app_did_enter_background",
                details: ["route": rootRoute.diagnosticName]
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            AppDiagnosticsRecorder.shared.record(
                "app_will_terminate",
                level: .warning,
                details: ["route": rootRoute.diagnosticName]
            )
        }
        .onChange(of: authVM.user?.uid) { _, _ in
            moderationStore.clear()
            AppDiagnosticsRecorder.shared.record(
                "auth_user_changed",
                details: [
                    "has_user": authVM.user == nil ? "false" : "true",
                    "route": rootRoute.diagnosticName
                ]
            )
            Task {
                postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
                advancePostAuthOnboardingPastDisplayNameIfAvailable()
                completePostAuthOnboardingIfRemoteProfileExists()
                await monetizationManager.refreshEntitlements()
                await bootstrapAuthenticatedLocalState()
                await PushNotificationService.shared.synchronizeAuthenticatedDeviceIfNeeded()
            }
        }
        .onChange(of: authVM.hasRemoteDisplayName) { _, _ in
            advancePostAuthOnboardingPastDisplayNameIfAvailable()
            completePostAuthOnboardingIfRemoteProfileExists()
        }
        .onChange(of: authVM.isProfileLoaded) { _, _ in
            advancePostAuthOnboardingPastDisplayNameIfAvailable()
            completePostAuthOnboardingIfRemoteProfileExists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .postAuthOnboardingStateDidChange)) { _ in
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid, force: true)
            advancePostAuthOnboardingPastDisplayNameIfAvailable()
        }
    }

    private var rootRoute: AppRootRoute {
        let resolvedRoute = AppRootRouteResolver.resolve(
            authenticationState: authVM.authenticationState,
            userId: authVM.user?.uid,
            postAuthOnboardingPhase: postAuthOnboardingCoordinator.phase,
            entitlementState: monetizationManager.entitlementStateForRouting,
            requiredEntitlementID: monetizationManager.configuration.revenueCatEntitlementID,
            allowsUnentitledAppAccess: monetizationManager.allowsUnentitledAppAccessForRouting
        )

        if case .onboarding(.displayName) = resolvedRoute,
           authVM.user != nil,
           !authVM.isProfileLoaded {
            return .resolving
        }

        return resolvedRoute
    }

    @ViewBuilder
    private func authenticatedContent(for route: AppRootRoute) -> some View {
        if let accountDataConflict {
            AccountDataConflictView(
                conflict: accountDataConflict,
                onSignOut: authVM.signOut
            )
        } else {
            switch route {
            case .signedOut:
                LandingScreen()
            case .signingIn:
                ProgressView("Signing In...")
                    .themedBackground()
            case .restoringSession:
                ProgressView("Restoring Session...")
                    .themedBackground()
            case .resolving:
                AppAccessResolvingView(onSignOut: authVM.signOut)

            case .onboarding(let stage):
                PostAuthOnboardingFlowView(
                    stage: stage,
                    onBack: postAuthOnboardingCoordinator.moveBack,
                    onContinue: postAuthOnboardingCoordinator.completeCurrentStage
                )

            case .paywall:
                AppAccessPaywallPlaceholderView()

            case .mainApp:
                MainTabView(tabRouter: tabRouter)
            }
        }
    }

    @MainActor
    private func bootstrapAuthenticatedLocalState() async {
        guard let user = authVM.user else {
            accountDataConflict = nil
            moderationStore.clear()
            return
        }
        let currentUserId = user.uid

        do {
            await moderationStore.hydrate(for: currentUserId)

            switch try AccountDataOwnershipService.evaluateAccess(
                modelContext: modelContext,
                signedInUserId: currentUserId
            ) {
            case .allowed:
                accountDataConflict = nil
            case .blocked(let conflict):
                accountDataConflict = conflict
                return
            }

            try WorkoutRemoteSyncMigrationService.runIfNeeded(
                modelContext: modelContext,
                currentUserId: currentUserId
            )
            AccountDataOwnershipService.recordAuthorizedOwner(signedInUserId: currentUserId)

            do {
                _ = try await WorkoutHydrationService.hydrateIfNeeded(
                    modelContext: modelContext,
                    currentUserId: currentUserId
                )
            } catch {
                debugLog("Workout hydration failed: \(error)")
            }

            // Pull the server-derived completed-climb projection into the cache
            // so the globe / Collection / totalClimbsCompleted are correct on an
            // in-place UPDATE too, not just a reinstall - independent of whether
            // the legacy hydration path ran on this install.
            await ClimbCompletionRepository.shared.refresh(
                userId: currentUserId,
                modelContext: modelContext
            )

            await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                modelContext: modelContext,
                currentUserId: currentUserId
            )

            let leaderboardService = LeaderboardService.shared
            leaderboardService.configure(modelContext: modelContext)

            let workouts = try modelContext.fetch(
                FetchDescriptor<Workout>(
                    predicate: #Predicate<Workout> { workout in
                        workout.ownerUserId == currentUserId
                    },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
            )
            let didRebuild = try leaderboardService.rebuildCurrentStatsIfNeeded(
                for: currentUserId,
                workouts: workouts
            )

            if didRebuild {
                try await leaderboardService.deleteLegacyRemoteStats(userId: currentUserId)
                await LeaderboardSessionCache.shared.invalidateAll()
            }

            await LeaderboardSyncCoordinator.shared.enqueueSync(
                userId: currentUserId
            )

            await ProfilePublicationService.publishCurrentUserProfile(
                modelContext: modelContext,
                userId: currentUserId,
                joinedAt: user.metadata.creationDate
            )
        } catch {
            debugLog("Authenticated bootstrap failed: \(error)")
        }
    }

    @MainActor
    private func advancePostAuthOnboardingPastDisplayNameIfAvailable() {
        guard authVM.user != nil,
              authVM.isProfileLoaded,
              hasUsableDisplayNameForPostAuthOnboarding else { return }

        postAuthOnboardingCoordinator.completeDisplayNameIfNeeded()
    }

    private var hasUsableDisplayNameForPostAuthOnboarding: Bool {
        authVM.hasRemoteDisplayName ||
        !authVM.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func completePostAuthOnboardingIfRemoteProfileExists() {
        #if DEBUG
        if let userId = authVM.user?.uid,
           PostAuthOnboardingStore().isDebugReplayActive(for: userId) {
            profileCompletionCheckTask?.cancel()
            profileCompletionCheckTask = nil
            return
        }
        #endif

        guard let user = authVM.user,
              authVM.isProfileLoaded,
              authVM.hasRemoteDisplayName else {
            profileCompletionCheckTask?.cancel()
            profileCompletionCheckTask = nil
            return
        }

        profileCompletionCheckTask?.cancel()
        profileCompletionCheckTask = Task { @MainActor in
            let userData = try? await UserDataRepository.shared.getUserFromFirestore(userId: user.uid)
            guard !Task.isCancelled,
                  let userData,
                  isCompletePostAuthProfile(userData) else {
                return
            }

            postAuthOnboardingCoordinator.markCurrentUserComplete()
        }
    }

    private func isCompletePostAuthProfile(_ userData: UserDisplayNameData) -> Bool {
        guard let displayName = userData.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty,
              let age = userData.age,
              (13...120).contains(age),
              let genderRawValue = userData.gender,
              ProfileGender(rawValue: genderRawValue) != nil,
              let weightKg = userData.weightKg,
              weightKg > 0,
              weightKg <= 400,
              let locationCity = userData.locationCity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locationCity.isEmpty,
              locationCity.count <= 120,
              let locationCountry = userData.locationCountry,
              locationCountry.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil else {
            return false
        }

        if let locationRegion = userData.locationRegion?.trimmingCharacters(in: .whitespacesAndNewlines),
           locationRegion.count > 120 {
            return false
        }

        return true
    }
}

private struct AccountDataConflictView: View {
    let conflict: AccountDataOwnershipConflict
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.ascendAccent)
                    .accessibilityHidden(true)

                Text("Account data mismatch")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("This device already has Ascend data for another account. Sign in with the original account to protect your workouts and rankings.")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onSignOut) {
                Text("Sign Out")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.ascendAccent)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign Out")

            Spacer()
        }
        .padding(.horizontal, 28)
        .themedBackground()
    }
}

private extension AppRootRoute {
    var diagnosticName: String {
        switch self {
        case .signedOut:
            return "signed_out"
        case .signingIn:
            return "signing_in"
        case .restoringSession:
            return "restoring_session"
        case .resolving:
            return "resolving"
        case .onboarding:
            return "onboarding"
        case .paywall:
            return "paywall"
        case .mainApp:
            return "main_app"
        }
    }
}

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
