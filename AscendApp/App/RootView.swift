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
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var postAuthOnboardingCoordinator = PostAuthOnboardingCoordinator()
    @State private var accountDataConflict: AccountDataOwnershipConflict?

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
        .animation(.easeInOut(duration: 0.25), value: rootRoute)
        .themeAware()
        .task {
            importCoordinator.configure(modelContext: modelContext)
            postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
            await monetizationManager.refreshEntitlements()
            // Resume any pending uploads from previous session
            await uploadManager.processPendingUploads(modelContext: modelContext)
            await bootstrapAuthenticatedLocalState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Retry pending uploads when app comes to foreground (network may have restored)
            Task {
                importCoordinator.configure(modelContext: modelContext)
                await monetizationManager.refreshEntitlements()
                await uploadManager.processPendingUploads(modelContext: modelContext)
                await bootstrapAuthenticatedLocalState()
            }
        }
        .onChange(of: authVM.user?.uid) { _, _ in
            Task {
                postAuthOnboardingCoordinator.resolve(userId: authVM.user?.uid)
                completePostAuthOnboardingIfRemoteProfileExists()
                await monetizationManager.refreshEntitlements()
                await bootstrapAuthenticatedLocalState()
            }
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
    }

    private var rootRoute: AppRootRoute {
        AppRootRouteResolver.resolve(
            authenticationState: authVM.authenticationState,
            userId: authVM.user?.uid,
            postAuthOnboardingPhase: postAuthOnboardingCoordinator.phase,
            entitlementState: monetizationManager.entitlementState,
            requiredEntitlementID: monetizationManager.configuration.revenueCatEntitlementID,
            allowsUnentitledAppAccess: monetizationManager.configuration.allowsUnentitledAppAccess
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
                ProgressView("Setting Up...")
                    .themedBackground()

            case .onboarding(let stage):
                PostAuthOnboardingFlowView(
                    stage: stage,
                    onBack: postAuthOnboardingCoordinator.moveBack,
                    onContinue: postAuthOnboardingCoordinator.completeCurrentStage
                )

            case .paywall:
                AppAccessPaywallPlaceholderView(
                    onRestore: {
                        Task {
                            try? await monetizationManager.restorePurchases()
                        }
                    }
                )
                .onAppear {
                    LifecycleEventRecorder.shared.recordPaywallReached(
                        placement: SuperwallPlacement.appAccessGate.rawValue
                    )
                }

            case .mainApp:
                MainTabView()
            }
        }
    }

    @MainActor
    private func bootstrapAuthenticatedLocalState() async {
        guard let user = authVM.user else {
            accountDataConflict = nil
            return
        }
        let currentUserId = user.uid

        do {
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
                print("Workout hydration failed: \(error)")
            }

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

            let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = cachedDisplayName?.isEmpty == false ? cachedDisplayName! : authVM.displayName
            let photoURL = UserDataRepository.shared.getCachedProfilePictureURL().flatMap(URL.init(string:)) ?? authVM.displayPhotoURL
            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            await LeaderboardSyncCoordinator.shared.enqueueSync(
                userId: currentUserId,
                displayName: displayName,
                photoURL: photoURL
            )

            await ProfilePublicationService.publishCurrentUserProfile(
                modelContext: modelContext,
                userId: currentUserId,
                displayName: displayName,
                photoURL: photoURL,
                joinedAt: user.metadata.creationDate
            )
        } catch {
            print("Authenticated bootstrap failed: \(error)")
        }
    }

    @MainActor
    private func completePostAuthOnboardingIfRemoteProfileExists() {
        guard authVM.user != nil,
              authVM.isProfileLoaded,
              authVM.hasRemoteDisplayName else {
            return
        }

        postAuthOnboardingCoordinator.markCurrentUserComplete()
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
                    .foregroundStyle(Color.accentColor)
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
                            .fill(Color.accentColor)
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

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
