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
    @Environment(\.openURL) private var openURL
    @State private var appVersionGateState = AppVersionGateState.shared
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var postAuthOnboardingCoordinator = PostAuthOnboardingCoordinator()
    @State private var tabRouter = TabRouter()
    @State private var accountDataConflict: AccountDataOwnershipConflict?
    @State private var isShowingGateAccountDeletion = false
    @State private var isGateDeletionUnresolved = false
    @State private var isGateDeletionDismissPending = false
    @State private var profileCompletionCheckTask: Task<Void, Never>?
    private let authenticatedBootstrapCoordinator = AuthenticatedBootstrapCoordinator.shared

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
        .sheet(item: $appVersionGateState.presentation) { presentation in
            AppUpdateSheet(
                presentation: presentation,
                onOpenAppStore: openAscendInAppStore,
                onLater: appVersionGateState.dismissRecommended
            )
        }
        // Deliberately outside the route switch: an entitlement refresh mid-deletion flips the
        // route, and unmounting this sheet would cancel the deletion partway through its sweep
        // with the failure alert on a view that is no longer on screen.
        .sheet(isPresented: $isShowingGateAccountDeletion, onDismiss: resetGateAccountDeletionState) {
            // Deleting the Firebase Auth account moves `authVM` to unauthenticated on its own,
            // which routes back to the landing screen - there is nothing left here to dismiss the
            // way Settings does.
            DeleteAccountConfirmationView(
                onAccountDeleted: {},
                onDeletionUnresolvedChange: gateAccountDeletionDidChangeResolution
            )
        }
        .task {
            AppDiagnosticsRecorder.shared.record(
                "app_root_task_started",
                details: ["route": rootRoute.diagnosticName]
            )
            importCoordinator.configure(modelContext: modelContext)
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
            advancePostAuthOnboardingPastDisplayNameIfAvailable()
            scheduleAuthenticatedSessionWork()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            AppDiagnosticsRecorder.shared.record(
                "app_will_enter_foreground",
                details: ["route": rootRoute.diagnosticName]
            )
            // Retry pending uploads when app comes to foreground (network may have restored)
            importCoordinator.configure(modelContext: modelContext)
            scheduleAuthenticatedSessionWork()
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
            // The sheet belongs to the session that opened it, or it re-presents itself unprompted
            // over the next climber's gate. But deletion ends the session at the auth step, several
            // steps before the local sweep finishes, so the clear waits for the dialog to say it is
            // done rather than for the session to end.
            dismissGateAccountDeletionWhenResolved()
            moderationStore.clear()
            AppDiagnosticsRecorder.shared.record(
                "auth_user_changed",
                details: [
                    "has_user": authVM.user == nil ? "false" : "true",
                    "route": rootRoute.diagnosticName
                ]
            )
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
            advancePostAuthOnboardingPastDisplayNameIfAvailable()
            completePostAuthOnboardingIfRemoteProfileExists()
            scheduleAuthenticatedSessionWork()
        }
        // A purchase completing mid-session flips this through RevenueCat's customer-info stream
        // without any refresh call, and that is exactly the moment the backend has not heard about
        // the purchase yet.
        .onChange(of: monetizationManager.hasAppAccess) { _, hasAccess in
            guard hasAccess else { return }
            Task {
                await monetizationManager.reconcileServerAppAccess()
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
        .onChange(of: onboardingFlowCompletionCandidate, initial: true) { _, reason in
            guard let reason else { return }
            OnboardingFlowAnalyticsCoordinator.shared.recordFlowCompletedIfNeeded(reason: reason)
        }
    }

    @MainActor
    private func dismissGateAccountDeletionWhenResolved() {
        guard isGateDeletionUnresolved else {
            isShowingGateAccountDeletion = false
            return
        }

        isGateDeletionDismissPending = true
    }

    @MainActor
    private func gateAccountDeletionDidChangeResolution(_ isUnresolved: Bool) {
        isGateDeletionUnresolved = isUnresolved
        guard !isUnresolved, isGateDeletionDismissPending else { return }

        isGateDeletionDismissPending = false
        isShowingGateAccountDeletion = false
    }

    @MainActor
    private func resetGateAccountDeletionState() {
        isGateDeletionUnresolved = false
        isGateDeletionDismissPending = false
    }

    private func openAscendInAppStore() {
        guard let url = AscendAppStoreDestination.productURL else { return }
        openURL(url)
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

    private var onboardingFlowCompletionCandidate: OnboardingFlowCompletionReason? {
        OnboardingFlowCompletionResolver.completionReason(
            rootRoute: rootRoute,
            postAuthPhase: postAuthOnboardingCoordinator.phase,
            confirmedAccessReason: monetizationManager.onboardingCompletionReasonForActiveAccess
        )
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
                AppAccessPaywallPlaceholderView(
                    onDeleteAccount: { isShowingGateAccountDeletion = true }
                )

            case .mainApp:
                MainTabView(tabRouter: tabRouter)
            }
        }
    }

    @MainActor
    private func scheduleAuthenticatedSessionWork() {
        let expectedUserId = authVM.user?.uid

        authenticatedBootstrapCoordinator.schedule {
            guard let expectedUserId,
                  isCurrentAuthenticatedSession(expectedUserId) else {
                accountDataConflict = nil
                moderationStore.clear()
                return
            }

            await monetizationManager.refreshEntitlements()
            guard isCurrentAuthenticatedSession(expectedUserId) else { return }

            await uploadManager.processPendingUploads(modelContext: modelContext)
            guard isCurrentAuthenticatedSession(expectedUserId) else { return }

            await bootstrapAuthenticatedLocalState(expectedUserId: expectedUserId)
            guard isCurrentAuthenticatedSession(expectedUserId) else { return }

            await PushNotificationService.shared.synchronizeAuthenticatedDeviceIfNeeded()
        }
    }

    private func bootstrapAuthenticatedLocalState(expectedUserId currentUserId: String) async {
        guard isCurrentAuthenticatedSession(currentUserId),
              let user = authVM.user else {
            accountDataConflict = nil
            moderationStore.clear()
            return
        }

        do {
            await moderationStore.hydrate(for: currentUserId)
            guard isCurrentAuthenticatedSession(currentUserId) else { return }

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

            try RoutineRemoteSyncAdoptionService.runIfNeeded(
                modelContext: modelContext,
                currentUserId: currentUserId
            )

            do {
                _ = try await WorkoutHydrationService.hydrateIfNeeded(
                    modelContext: modelContext,
                    currentUserId: currentUserId
                )
            } catch is CancellationError {
                return
            } catch {
                debugLog("Workout hydration failed: \(error)")
            }
            guard isCurrentAuthenticatedSession(currentUserId) else { return }

            // Restoring routines is independent of workouts, so a failure on
            // either side must not take the other down with it.
            do {
                _ = try await RoutineHydrationService.hydrateIfNeeded(
                    modelContext: modelContext,
                    currentUserId: currentUserId
                )
            } catch is CancellationError {
                return
            } catch {
                debugLog("Routine hydration failed: \(error)")
            }
            guard isCurrentAuthenticatedSession(currentUserId) else { return }

            // Pull the server-derived completed-climb projection into the cache
            // so the globe / Collection / totalClimbsCompleted are correct on an
            // in-place UPDATE too, not just a reinstall - independent of whether
            // the legacy hydration path ran on this install.
            await ClimbCompletionRepository.shared.refresh(
                userId: currentUserId,
                modelContext: modelContext
            )
            guard isCurrentAuthenticatedSession(currentUserId) else { return }

            await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                modelContext: modelContext,
                currentUserId: currentUserId
            )
            guard isCurrentAuthenticatedSession(currentUserId) else { return }

            await RoutineSyncCoordinator.shared.processPendingRoutines(
                modelContext: modelContext,
                currentUserId: currentUserId
            )
            guard isCurrentAuthenticatedSession(currentUserId) else { return }

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
                await LeaderboardSessionCache.shared.invalidateAll()
            }

            await ProfilePublicationService.publishCurrentUserProfile(
                modelContext: modelContext,
                userId: currentUserId,
                joinedAt: user.metadata.creationDate
            )
        } catch is CancellationError {
            return
        } catch {
            debugLog("Authenticated bootstrap failed: \(error)")
        }
    }

    private func isCurrentAuthenticatedSession(_ expectedUserId: String) -> Bool {
        Task.isCancelled == false && authVM.user?.uid == expectedUserId
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

struct AccountDataConflictView: View {
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

                Text("This device holds Ascend data created by another account. Sign out to keep it intact, then sign in with that account.")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onSignOut) {
                Text("Sign Out and Keep Data")
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
            .accessibilityLabel("Sign Out and Keep Data")

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
