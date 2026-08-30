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
    @State private var enrichmentService = AppleHealthEnrichmentService.shared
    @State private var postAuthOnboardingCoordinator = PostAuthOnboardingCoordinator()
    @State private var tabRouter = TabRouter()
    @State private var accountDataConflict: AccountDataOwnershipConflict?
    @State private var isShowingGateAccountDeletion = false
    @State private var isGateDeletionUnresolved = false
    @State private var isGateDeletionDismissPending = false
    @State private var gateAccountDeletionDismissalRevision: UInt = 0
    @State private var profileCompletionCheckTask: Task<Void, Never>?
    private let authenticatedBootstrapCoordinator = AuthenticatedBootstrapCoordinator.shared
    private let appSessionTelemetryCoordinator = AppSessionTelemetryCoordinator.shared

    var body: some View {
        Group {
            switch rootRoute {
            case .updateRequired:
                routeContent(for: rootRoute)
            case .signedOut:
                routeContent(for: rootRoute)
            case .signingIn:
                routeContent(for: rootRoute)
            case .restoringSession:
                routeContent(for: rootRoute)
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
        // The soft nudge only. The lockout left this modifier when it became a route, so the two
        // can never stack and nothing presented outside this hierarchy can cover the refusal.
        .sheet(item: $appVersionGateState.nudgePresentation) { presentation in
            AppUpdateSheet(
                presentation: presentation,
                onOpenAppStore: openAscendInAppStore,
                onLater: appVersionGateState.dismissRecommended
            )
            .trackOnce(screen: .appUpdateNudge)
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
            observeColdLaunchSession()
            AppDiagnosticsRecorder.shared.record(
                "app_root_task_started",
                details: ["route": rootRoute.diagnosticName]
            )
            enrichmentService.configure(modelContext: modelContext)
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
            scheduleAuthenticatedSessionWork()
        }
        // Its own task so the catalogue fetch runs alongside session work rather
        // than behind it: pre-auth onboarding quotes the raceable count, and it
        // is reachable a tap after launch.
        .task {
            await RaceableClimbCountStore.shared.resolve()
        }
        // The launch route and the authentication answer both land after the root task's first
        // tick, and either can settle without moving the other - a lockout resolves above auth, and
        // entitlement resolves long after it. So the cold-launch session watches both.
        .onChange(of: rootRoute) { _, _ in
            observeColdLaunchSession()
        }
        .onChange(of: coldLaunchAuthState) { _, _ in
            observeColdLaunchSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            appSessionTelemetryCoordinator.recordWillEnterForeground(
                rootRoute: rootRoute,
                authenticationState: authVM.authenticationState
            )
            AppDiagnosticsRecorder.shared.record(
                "app_will_enter_foreground",
                details: ["route": rootRoute.diagnosticName]
            )
            // Retry pending uploads when app comes to foreground (network may have restored)
            AppleHealthEnrichmentService.shared.configure(modelContext: modelContext)
            scheduleAuthenticatedSessionWork()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            appSessionTelemetryCoordinator.recordDidEnterBackground()
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
        // The lockout suppresses the session bootstrap, and the fetch that releases it lands after
        // the foreground handler has already run and skipped. Without this, entitlement refresh,
        // pending uploads, hydration, both sync coordinators and profile publication stay skipped
        // until a further background/foreground cycle.
        .onChange(of: appVersionGateState.isUpdateRequired) { _, isUpdateRequired in
            guard !isUpdateRequired else { return }
            scheduleAuthenticatedSessionWork()
        }
        .onChange(of: authVM.hasRemoteDisplayName) { _, _ in
            completePostAuthOnboardingIfRemoteProfileExists()
        }
        .onChange(of: authVM.isProfileLoaded) { _, _ in
            completePostAuthOnboardingIfRemoteProfileExists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .postAuthOnboardingStateDidChange)) { _ in
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid, force: true)
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
        gateAccountDeletionDismissalRevision &+= 1
    }

    private func openAscendInAppStore() {
        guard let url = AscendAppStoreDestination.productURL else { return }
        openURL(url)
    }

    /// Deletion is only an exit for a climber who has an account. The lockout resolves above
    /// authentication, so the route is reachable with no session at all - and there the link would
    /// be a dead end rather than the required way out.
    private var gateAccountDeletionAction: (() -> Void)? {
        guard authVM.user != nil else { return nil }

        return { isShowingGateAccountDeletion = true }
    }

    private var rootRoute: AppRootRoute {
        let resolvedRoute = AppRootRouteResolver.resolve(
            updatePresentation: appVersionGateState.presentation,
            authenticationState: authVM.authenticationState,
            userId: authVM.user?.uid,
            postAuthOnboardingPhase: postAuthOnboardingCoordinator.phase,
            entitlementState: monetizationManager.entitlementStateForRouting,
            requiredEntitlementID: monetizationManager.configuration.revenueCatEntitlementID,
            allowsUnentitledAppAccess: monetizationManager.allowsUnentitledAppAccessForRouting
        )

        // At the very start of onboarding we do not yet know whether this account
        // already finished it on another device, and `completePostAuthOnboardingIfRemoteProfileExists`
        // cannot answer that until the profile has loaded. Holding here is what
        // stops the first question flashing at a climber who has already answered
        // it. Deliberately keyed to `.first` rather than to a named stage: the
        // stage that opens onboarding has changed once already.
        if case .onboarding(let stage) = resolvedRoute,
           stage == .first,
           authVM.user != nil,
           !authVM.isProfileLoaded {
            return .resolving
        }

        return resolvedRoute
    }

    private var coldLaunchAuthState: AppLifecycleAnalyticsEvent.AuthState {
        AppLifecycleAnalyticsEvent.AuthState(authVM.authenticationState)
    }

    @MainActor
    private func observeColdLaunchSession() {
        appSessionTelemetryCoordinator.observeColdLaunch(
            rootRoute: rootRoute,
            authenticationState: authVM.authenticationState
        )
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
            .trackOnce(screen: .accountDataConflict)
        } else {
            routeContent(for: route)
        }
    }

    /// The one route-to-view mapping, shared by both callers so a route is spelled once.
    ///
    /// Exhaustive on purpose: a new `AppRootRoute` case has to be given a view here and a
    /// screen name in `AppRootRoute.telemetryScreenName`, or the app does not compile.
    /// The routing decision stays in `body` - `authenticatedContent` first has to answer the
    /// account-data conflict, and sending the landing screen or the update lockout through
    /// that check would let a stale conflict cover a refusal the climber cannot leave.
    @ViewBuilder
    private func routeContent(for route: AppRootRoute) -> some View {
        switch route {
        case .updateRequired:
            routeScreen(route) {
                AppUpdateRequiredView(
                    onOpenAppStore: openAscendInAppStore,
                    onDeleteAccount: gateAccountDeletionAction
                )
            }

        case .signedOut:
            routeScreen(route) {
                LandingScreen()
            }

        case .signingIn:
            routeScreen(route) {
                ProgressView("Signing In...")
                    .themedBackground()
            }

        case .restoringSession:
            routeScreen(route) {
                ProgressView("Restoring Session...")
                    .themedBackground()
            }

        case .resolving:
            routeScreen(route) {
                AppAccessResolvingView(onSignOut: authVM.signOut)
            }

        case .onboarding(let stage):
            routeScreen(route) {
                PostAuthOnboardingFlowView(
                    stage: stage,
                    onBack: postAuthOnboardingCoordinator.moveBack,
                    onContinue: postAuthOnboardingCoordinator.completeCurrentStage
                )
            }

        case .paywall:
            routeScreen(route) {
                AppAccessPaywallPlaceholderView(
                    accountDeletionDismissalRevision: gateAccountDeletionDismissalRevision,
                    onDeleteAccount: { isShowingGateAccountDeletion = true },
                    onSignOut: authVM.signOut
                )
            }

        case .mainApp:
            routeScreen(route) {
                MainTabView(tabRouter: tabRouter)
            }
        }
    }

    /// Reports the route's screen from inside its own switch branch.
    ///
    /// Deliberately not one modifier above the switch: the once-per-appearance guard belongs
    /// to a view instance, and a single instance spanning every route would report the first
    /// route the app resolved and then stay silent for the rest of the session. Each branch
    /// is its own identity, so a route change tears the guard down and the next route
    /// reports itself.
    ///
    /// The stage of an `.onboarding` route is not an identity change, so a climber walking
    /// the post-auth flow banks one `onboarding_flow` view, not one per step - the 21 steps
    /// are the onboarding funnel's job.
    @ViewBuilder
    private func routeScreen(
        _ route: AppRootRoute,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if let screen = route.telemetryScreenName {
            content().trackOnce(screen: screen)
        } else {
            content()
        }
    }

    @MainActor
    private func scheduleAuthenticatedSessionWork() {
        // A build the operator retired does not get to keep hydrating, syncing and publishing
        // behind a screen the climber cannot leave. The lockout refuses the binary, not just its UI.
        guard !appVersionGateState.isUpdateRequired else { return }

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

            // The only place enrichment is re-armed, and deliberately inside this chain rather
            // than beside it in the foreground handler. A suspended app is not a reliable alarm
            // clock - the timer's sleep does not advance while the process is frozen - so a
            // foreground has to service a schedule that came due overnight, and this chain runs
            // on foreground too. What it must not do is run while the update lockout is up:
            // a pass writes through `WorkoutMutationHandler`, which marks pending remote upserts,
            // rebuilds the leaderboard and kicks the sync coordinator and profile publication, so
            // re-arming outside `scheduleAuthenticatedSessionWork`'s guard let a binary the
            // operator retired go on writing behind a screen the climber cannot leave.
            //
            // Placed after hydration so a climb restored onto a fresh device is tracked too, and
            // before the leaderboard rebuild because enrichment only ever adds metrics that
            // rebuild already reads.
            AppleHealthEnrichmentService.shared.resumeTracking(modelContext: modelContext)

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
    /// Deliberately the analytics mapping rather than a second one: a diagnostics breadcrumb and a
    /// session event that name the same route differently split one stream into two.
    var diagnosticName: String {
        AppLifecycleAnalyticsEvent.RootRoute(self).rawValue
    }
}

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
