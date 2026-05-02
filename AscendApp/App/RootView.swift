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
    @Environment(\.modelContext) private var modelContext
    @Environment(MediaUploadManager.self) private var uploadManager
    @State private var importCoordinator = WorkoutImportCoordinator.shared

    var body: some View {
        Group {
            switch authVM.authenticationState {
            case .authenticated, .restoringSession:
                MainTabView()
            case .authenticatingWithApple,
                 .authenticatingWithGoogle,
                 .authenticatingWithInternalQA:
                ProgressView("Signing In...")
                    .themedBackground()
            case .unauthenticated:
                LandingScreen()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authVM.authenticationState)
        .themeAware()
        .task {
            importCoordinator.configure(modelContext: modelContext)
            // Resume any pending uploads from previous session
            await uploadManager.processPendingUploads(modelContext: modelContext)
            await bootstrapAuthenticatedLocalState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Retry pending uploads when app comes to foreground (network may have restored)
            Task {
                importCoordinator.configure(modelContext: modelContext)
                await uploadManager.processPendingUploads(modelContext: modelContext)
                await bootstrapAuthenticatedLocalState()
            }
        }
        .onChange(of: authVM.user?.uid) { _, _ in
            Task {
                await bootstrapAuthenticatedLocalState()
            }
        }
    }

    @MainActor
    private func bootstrapAuthenticatedLocalState() async {
        guard let user = authVM.user else { return }

        do {
            try WorkoutRemoteSyncMigrationService.runIfNeeded(
                modelContext: modelContext,
                currentUserId: user.uid
            )

            await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                modelContext: modelContext,
                currentUserId: user.uid
            )

            let leaderboardService = LeaderboardService.shared
            leaderboardService.configure(modelContext: modelContext)

            let workouts = try modelContext.fetch(
                FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
            )
            let didRebuild = try leaderboardService.rebuildCurrentStatsIfNeeded(
                for: user.uid,
                workouts: workouts
            )

            if didRebuild {
                try await leaderboardService.deleteLegacyRemoteStats(userId: user.uid)
                await LeaderboardSessionCache.shared.invalidateAll()
            }

            let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = cachedDisplayName?.isEmpty == false ? cachedDisplayName! : authVM.displayName
            let photoURL = UserDataRepository.shared.getCachedProfilePictureURL().flatMap(URL.init(string:)) ?? authVM.displayPhotoURL

            await LeaderboardSyncCoordinator.shared.enqueueSync(
                userId: user.uid,
                displayName: displayName,
                photoURL: photoURL
            )
        } catch {
            print("Authenticated bootstrap failed: \(error)")
        }
    }
}

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
