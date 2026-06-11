//
//  DebugToolsViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import FirebaseAuth
import Observation
import SwiftData

#if DEBUG
@MainActor
@Observable
class DebugToolsViewModel {
    private let service = DebugToolsService.shared

    private enum ActionTitle {
        static let seedLeaderboard = "Seed Test Data"
        static let clearLeaderboard = "Clear Test Data"
        static let seedWorkouts = "Seed Workouts"
        static let clearSeededWorkouts = "Clear Seeded Workouts"
        static let queueAutoImportReview = "Queue Auto-Import Review"
        static let clearAutoImportSimulations = "Clear Auto-Import Simulations"
        static let resetPostAuthOnboarding = "Reset Post-Auth Onboarding"
        static let replayPostAuthOnboarding = "Replay Onboarding Now"
        static let replayFullOnboardingFromLanding = "Replay From Landing"
        static let completePostAuthOnboarding = "Complete Post-Auth Onboarding"
    }

    var selectedWorkoutPreset: WorkoutSeedPreset = .appStoreScreenshots
    var executingActionId: UUID?  // Track which specific action is executing
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Debug Sections Configuration

    var sections: [DebugSection] {
        [
            onboardingSection,
            appleHealthImportSection,
            workoutsSection,
            leaderboardSection
        ]
    }

    // MARK: - Onboarding Section

    private var onboardingSection: DebugSection {
        DebugSection(
            title: "Onboarding",
            subtitle: "Replay the onboarding funnel for the current account without creating a new user",
            actions: [
                DebugAction(
                    title: ActionTitle.replayPostAuthOnboarding,
                    description: "Starts the signed-in post-auth onboarding flow from the first profile screen and temporarily disables the remote-profile auto-skip.",
                    icon: "play.circle.fill",
                    iconColor: .accent
                ),
                DebugAction(
                    title: ActionTitle.replayFullOnboardingFromLanding,
                    description: "Sets the same replay flag, signs out, then lets you start from the landing screen and log back into this same account.",
                    icon: "rectangle.portrait.and.arrow.right",
                    iconColor: .orange
                ),
                DebugAction(
                    title: ActionTitle.completePostAuthOnboarding,
                    description: "Marks the current account as having completed the post-auth onboarding flow.",
                    icon: "checkmark.seal.fill",
                    iconColor: .green
                )
            ]
        )
    }

    // MARK: - Apple Health Section

    private var appleHealthImportSection: DebugSection {
        DebugSection(
            title: "Apple Health Import",
            subtitle: "Simulator hooks for the auto-import review flow",
            actions: [
                DebugAction(
                    title: ActionTitle.queueAutoImportReview,
                    description: "Creates a synthetic Apple Health import, queues it for review, and waits for the next foreground activation to present the full-screen review flow.",
                    icon: "rectangle.stack.badge.plus",
                    iconColor: .accent
                ),
                DebugAction(
                    title: ActionTitle.clearAutoImportSimulations,
                    description: "Removes only the synthetic Apple Health auto-import workouts created from Debug Tools.",
                    icon: "trash.fill",
                    iconColor: .red,
                    isDestructive: true
                )
            ]
        )
    }

    // MARK: - Workouts Section

    private var workoutsSection: DebugSection {
        DebugSection(
            title: "Workouts",
            subtitle: "Seed local SwiftData workout history",
            actions: [
                DebugAction(
                    title: ActionTitle.seedWorkouts,
                    description: "Seeds realistic local workout history for Simulator testing and screenshots.",
                    icon: "figure.stair.stepper",
                    iconColor: .accent
                ),
                DebugAction(
                    title: ActionTitle.clearSeededWorkouts,
                    description: "Clears only workouts seeded by Debug Tools.",
                    icon: "trash.fill",
                    iconColor: .red,
                    isDestructive: true
                )
            ]
        )
    }

    // MARK: - Leaderboard Section

    private var leaderboardSection: DebugSection {
        DebugSection(
            title: "Leaderboards",
            subtitle: "Manage test leaderboard data",
            actions: [
                DebugAction(
                    title: ActionTitle.seedLeaderboard,
                    description: "Seeds leaderboard entries for YOUR account across all time frames. For multi-user data, run: node scripts/seed-leaderboard.mjs seed --project dev",
                    icon: "arrow.down.doc.fill",
                    iconColor: .accent
                ),
                DebugAction(
                    title: ActionTitle.clearLeaderboard,
                    description: "Clears YOUR seeded leaderboard entries.",
                    icon: "trash.fill",
                    iconColor: .red,
                    isDestructive: true
                )
            ]
        )
    }

    // MARK: - Action Execution

    func executeAction(
        _ action: DebugAction,
        modelContext: ModelContext,
        authVM: AuthenticationViewModel
    ) async {
        executingActionId = action.id  // Set the specific action being executed
        errorMessage = nil
        successMessage = nil

        do {
            // Map action titles to service methods
            switch action.title {
            case ActionTitle.queueAutoImportReview:
                _ = try await service.queueSimulatedAppleHealthAutoImportReview(modelContext: modelContext)

            case ActionTitle.clearAutoImportSimulations:
                let count = try await service.clearSimulatedAppleHealthAutoImports(modelContext: modelContext)
                successMessage = "Cleared \(count) simulated auto-import workout\(count == 1 ? "" : "s")."

            case ActionTitle.resetPostAuthOnboarding:
                let userId = try currentUserId()
                PostAuthOnboardingStore().reset(for: userId)
                NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
                successMessage = "Reset post-auth onboarding for this user."

            case ActionTitle.replayPostAuthOnboarding:
                let userId = try currentUserId()
                PostAuthOnboardingStore().beginDebugReplay(for: userId)
                NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
                successMessage = "Started onboarding replay for this user."

            case ActionTitle.replayFullOnboardingFromLanding:
                let userId = try currentUserId()
                PostAuthOnboardingStore().beginDebugReplay(for: userId)
                NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
                authVM.signOut()
                successMessage = "Replay is ready. Sign back into this account from the landing screen."

            case ActionTitle.completePostAuthOnboarding:
                let userId = try currentUserId()
                PostAuthOnboardingStore().markComplete(for: userId)
                SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
                NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
                successMessage = "Marked post-auth onboarding complete for this user."

            case ActionTitle.seedWorkouts:
                let count = try await service.seedWorkoutData(
                    preset: selectedWorkoutPreset,
                    modelContext: modelContext
                )
                successMessage = "Seeded \(count) workout\(count == 1 ? "" : "s") using \(selectedWorkoutPreset.displayName)."

            case ActionTitle.clearSeededWorkouts:
                let count = try await service.clearSeededWorkoutData(modelContext: modelContext)
                successMessage = "Cleared \(count) seeded workout\(count == 1 ? "" : "s")."

            case ActionTitle.seedLeaderboard:
                try await service.seedLeaderboardData()
                successMessage = "Successfully seeded test data!"

            case ActionTitle.clearLeaderboard:
                try await service.clearLeaderboardData()
                successMessage = "Successfully cleared test data!"

            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        executingActionId = nil
    }

    // ✅ Helper to check if a specific action is executing
    func isExecuting(_ action: DebugAction) -> Bool {
        return executingActionId == action.id
    }

    private func currentUserId() throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw DebugOnboardingError.missingAuthenticatedUser
        }

        return userId
    }
}

private enum DebugOnboardingError: LocalizedError {
    case missingAuthenticatedUser

    var errorDescription: String? {
        "Sign in before changing onboarding debug state."
    }
}
#endif
