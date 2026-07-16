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
        static let forceAppAccessGate = "Force App Access Gate"
        static let clearAppAccessGateOverride = "Clear App Access Gate Override"
        static let presentAppAccessPaywall = "Present App Access Paywall"
        static let refreshEntitlements = "Refresh Entitlements"
        static let restorePurchases = "Restore Purchases"
        static let sendSentryTestDiagnostic = "Send Sentry Test Event"
    }

    var selectedWorkoutPreset: WorkoutSeedPreset = .appStoreScreenshots
    var executingActionId: UUID?  // Track which specific action is executing
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Debug Sections Configuration

    var sections: [DebugSection] {
        [
            diagnosticsSection,
            onboardingSection,
            monetizationSection,
            appleHealthImportSection,
            workoutsSection,
            leaderboardSection
        ]
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: DebugSection {
        DebugSection(
            title: "Diagnostics",
            subtitle: "Verify crash and non-fatal error reporting",
            actions: [
                DebugAction(
                    title: ActionTitle.sendSentryTestDiagnostic,
                    description: "Enables telemetry for this Debug session and sends a harmless non-fatal diagnostic event through Crashlytics and Sentry.",
                    icon: "waveform.path.ecg.rectangle.fill",
                    iconColor: .red
                )
            ]
        )
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

    // MARK: - Monetization Section

    private var monetizationSection: DebugSection {
        DebugSection(
            title: "Monetization",
            subtitle: "Exercise the RevenueCat and Superwall app-access flow without waiting for the production gate",
            actions: [
                DebugAction(
                    title: ActionTitle.forceAppAccessGate,
                    description: "Routes the dev app through the same hard-gate fallback screen used by staging, even when Debug would normally bypass app access.",
                    icon: "lock.fill",
                    iconColor: .orange
                ),
                DebugAction(
                    title: ActionTitle.clearAppAccessGateOverride,
                    description: "Clears the Debug-only hard-gate override and returns the dev app to normal unentitled access.",
                    icon: "lock.open.fill",
                    iconColor: .green
                ),
                DebugAction(
                    title: ActionTitle.presentAppAccessPaywall,
                    description: "Presents the app-access Superwall placement using the RevenueCat purchase controller.",
                    icon: "creditcard.fill",
                    iconColor: .accent
                ),
                DebugAction(
                    title: ActionTitle.refreshEntitlements,
                    description: "Fetches the latest RevenueCat customer info and updates local app-access state.",
                    icon: "arrow.clockwise.circle.fill",
                    iconColor: .blue
                ),
                DebugAction(
                    title: ActionTitle.restorePurchases,
                    description: "Runs RevenueCat restore purchases and updates local entitlement state.",
                    icon: "arrow.counterclockwise.circle.fill",
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

            case ActionTitle.presentAppAccessPaywall:
                guard MonetizationManager.shared.isSuperwallConfigured else {
                    throw DebugMonetizationError.superwallUnavailable
                }
                MonetizationManager.shared.presentPaywall(
                    .appAccessGate,
                    params: ["source": "debug_tools"]
                )

            case ActionTitle.forceAppAccessGate:
                MonetizationManager.shared.setDebugForcesAppAccessPaywall(true)
                successMessage = "Forced the app-access gate. The root view should switch to the paywall fallback screen."

            case ActionTitle.clearAppAccessGateOverride:
                MonetizationManager.shared.setDebugForcesAppAccessPaywall(false)
                successMessage = "Cleared the app-access gate override."

            case ActionTitle.refreshEntitlements:
                guard MonetizationManager.shared.isRevenueCatConfigured else {
                    throw DebugMonetizationError.revenueCatUnavailable
                }
                await MonetizationManager.shared.refreshEntitlements()
                successMessage = "Refreshed RevenueCat entitlements."

            case ActionTitle.restorePurchases:
                guard MonetizationManager.shared.isRevenueCatConfigured else {
                    throw DebugMonetizationError.revenueCatUnavailable
                }
                try await MonetizationManager.shared.restorePurchases()
                successMessage = "Restored purchases from RevenueCat."

            case ActionTitle.sendSentryTestDiagnostic:
                service.sendSentryTestDiagnostic()
                successMessage = "Sent a non-fatal Sentry test diagnostic."

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

private enum DebugMonetizationError: LocalizedError {
    case superwallUnavailable
    case revenueCatUnavailable

    var errorDescription: String? {
        switch self {
        case .superwallUnavailable:
            return "Superwall is not configured for this build."
        case .revenueCatUnavailable:
            return "RevenueCat is not configured for this build."
        }
    }
}
#endif
