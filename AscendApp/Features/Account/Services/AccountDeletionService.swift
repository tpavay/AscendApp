//
//  AccountDeletionService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import Foundation
import FirebaseAuth
import SwiftData

/// Service responsible for handling complete account deletion
/// Deletes data from: Firebase Auth, Firestore, Firebase Storage, local SwiftData, and local app caches
@MainActor
final class AccountDeletionService {

    enum DeletionError: LocalizedError {
        case notAuthenticated
        case firestoreDeletionFailed(String)
        case storageDeletionFailed(String)
        case authDeletionFailed(String)
        case localDataDeletionFailed(String)
        case reauthenticationFailed(String)
        case reauthenticationCancelled

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to delete your account."
            case .firestoreDeletionFailed(let message):
                return "Failed to delete cloud data: \(message)"
            case .storageDeletionFailed(let message):
                return "Failed to delete stored files: \(message)"
            case .authDeletionFailed(let message):
                return "Failed to delete account: \(message)"
            case .localDataDeletionFailed(let message):
                return "Failed to delete local data: \(message)"
            case .reauthenticationFailed(let message):
                return "Failed to verify your identity: \(message)"
            case .reauthenticationCancelled:
                return "Account deletion cancelled."
            }
        }
    }

    struct DeletionProgress {
        var currentStep: String
        var completedSteps: Int
        var totalSteps: Int

        var progressPercentage: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(completedSteps) / Double(totalSteps)
        }
    }

    private let gateway: AccountDeletionGateway
    private let localCleanup: AccountDeletionLocalCleanup

    init(
        gateway: AccountDeletionGateway = FirebaseAccountDeletionGateway(),
        localCleanup: AccountDeletionLocalCleanup = AppAccountDeletionLocalCleanup()
    ) {
        self.gateway = gateway
        self.localCleanup = localCleanup
    }

    /// Performs complete account deletion
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local data deletion
    ///   - progressHandler: Optional callback for progress updates
    func deleteAccount(
        modelContext: ModelContext,
        progressHandler: ((DeletionProgress) -> Void)? = nil
    ) async throws {
        guard let userId = gateway.currentUserId else {
            throw DeletionError.notAuthenticated
        }

        let totalSteps = 12
        var completedSteps = 0
        var hasStagedLocalDeletion = false
        var hasCommittedLocalDeletion = false

        defer {
            if hasStagedLocalDeletion && !hasCommittedLocalDeletion {
                modelContext.rollback()
            }
        }

        func updateProgress(_ step: String) {
            progressHandler?(DeletionProgress(
                currentStep: step,
                completedSteps: completedSteps,
                totalSteps: totalSteps
            ))
        }

        try Task.checkCancellation()

        // Step 1: Reauthenticate BEFORE any destructive work.
        // This is the only user-interactive step that can be cancelled.
        // By doing it first we guarantee that cancelling reauth leaves
        // all data intact — nothing has been deleted yet.
        updateProgress("Verifying your identity...")
        let reauthentication = try await ensureFreshAuthentication()
        completedSteps += 1
        try Task.checkCancellation()

        // ── From this point on, every step is non-interactive. ──

        // Revoke the Sign in with Apple token now, while the authorization code
        // captured during reauth is freshest. Apple codes expire in ~5 minutes
        // and the Storage/Firestore sweeps below can outlast that window for
        // heavy accounts on slow connections, so revoking here (rather than just
        // before deleteAuthAccount) avoids a silently-expired code defeating
        // 5.1.1(v). Revoking the Apple grant does not invalidate the Firebase
        // ID token, so the owner-gated deletes that follow still succeed.
        await revokeAppleTokenIfNeeded(reauthentication)
        try Task.checkCancellation()

        // Step 2: Delete all user-scoped Storage data (storage-level sweep)
        updateProgress("Deleting stored files...")
        try await deleteAllUserStorage(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 3: Delete any legacy flat-path files referenced by local records
        updateProgress("Cleaning up legacy media...")
        try await deleteLegacyFlatPathMedia(modelContext: modelContext)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 4: Delete Firestore leaderboard stats
        updateProgress("Deleting leaderboard data...")
        try await deleteLeaderboardStats(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 5: Delete Firestore rate-limit metadata
        updateProgress("Deleting feedback metadata...")
        try await deleteFeedbackRateLimitDocument(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 6: Delete Firestore workout backup documents
        updateProgress("Deleting workout backups...")
        try await deleteWorkoutBackups(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 7: Delete the publicly readable profile mirrors.
        //
        // This MUST happen before the auth account goes away (step 11):
        // firestore.rules gates these deletes on isOwner(userId), so once the
        // auth user is deleted no client can ever authenticate as this uid
        // again and the documents become orphaned PII that keeps the deleted
        // user visible on leaderboards and profiles.
        updateProgress("Deleting public profile...")
        try await deletePublicProfileMirrors(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 8: Deactivate push delivery while the callable can still
        // authenticate and while users/{uid} still exists. The Cloud Function
        // sweep remains authoritative if this best-effort request fails.
        updateProgress("Disabling notifications...")
        await gateway.unregisterPushDevice()
        completedSteps += 1
        try Task.checkCancellation()

        // Step 9: Delete Firestore user document.
        //
        // Deleting this fires the cleanupDeletedUserData Cloud Function, which
        // sweeps every remaining subcollection, including the server-owned ones
        // (achievements, lifecycle, integrations, ...) that no client is allowed
        // to touch, and anything the steps above left behind.
        updateProgress("Deleting user profile...")
        try await deleteUserDocument(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 10: Stage local deletion (rollback if auth deletion fails)
        updateProgress("Preparing local data cleanup...")
        try stageLocalDataDeletion(modelContext: modelContext)
        hasStagedLocalDeletion = true
        completedSteps += 1
        try Task.checkCancellation()

        // Step 11: Delete the Firebase Auth account (credentials already fresh
        // from Step 1, Apple token already revoked right after reauth).
        updateProgress("Deleting account...")
        try await deleteAuthAccount()
        completedSteps += 1
        try Task.checkCancellation()

        // Step 12: Commit local deletion and clear caches
        updateProgress("Finalizing local cleanup...")
        try commitStagedLocalDeletion(modelContext: modelContext)
        hasCommittedLocalDeletion = true
        try await clearLocalPendingUploadFiles()
        localCleanup.clearUserDefaults()
        localCleanup.clearImageCache()
        completedSteps += 1

        updateProgress("Account deleted successfully")
    }

    // MARK: - Authentication

    /// Proactively reauthenticates the user so that the interactive sign-in
    /// happens BEFORE any destructive operations. If the user cancels here,
    /// no data has been deleted yet.
    private func ensureFreshAuthentication() async throws -> ReauthenticationResult {
        do {
            return try await gateway.reauthenticate()
        } catch is CancellationError {
            throw DeletionError.reauthenticationCancelled
        } catch AccountDeletionGatewayError.notAuthenticated {
            throw DeletionError.notAuthenticated
        } catch AccountDeletionGatewayError.unknownProvider {
            throw DeletionError.reauthenticationFailed("Unknown sign-in provider")
        } catch let error as DeletionError {
            throw error
        } catch {
            throw DeletionError.reauthenticationFailed(error.localizedDescription)
        }
    }

    /// Revokes the user's Sign in with Apple token, which Apple has required on
    /// account deletion since 2022 (App Store guideline 5.1.1(v)). Without it
    /// the app keeps appearing under Settings > Apple ID > Sign in with Apple.
    ///
    /// Best-effort by design: revocation is a courtesy to Apple's account list,
    /// while failing to delete is a guideline violation the user feels directly.
    /// A transient revoke failure must not strand someone with an account they
    /// cannot delete, so this logs and lets deletion proceed.
    private func revokeAppleTokenIfNeeded(_ reauthentication: ReauthenticationResult) async {
        guard let authorizationCode = reauthentication.appleAuthorizationCode else { return }

        do {
            try await gateway.revokeAppleToken(authorizationCode: authorizationCode)
        } catch {
            debugLog("Sign in with Apple token revocation failed: \(error.localizedDescription)")
            TelemetryManager.shared.recordError(
                error,
                context: .auth,
                code: "apple_token_revocation_failed",
                additionalInfo: ["provider": "apple"]
            )
        }
    }

    /// Deletes Firebase Auth account. Credentials should already be fresh
    /// from ensureFreshAuthentication(), but handles requiresRecentLogin
    /// as a fallback just in case.
    private func deleteAuthAccount() async throws {
        do {
            try await gateway.deleteAuthAccount()
        } catch AccountDeletionGatewayError.notAuthenticated {
            throw DeletionError.notAuthenticated
        } catch let error as NSError {
            guard error.code == AuthErrorCode.requiresRecentLogin.rawValue else {
                throw DeletionError.authDeletionFailed(error.localizedDescription)
            }

            // This shouldn't happen since we reauthenticated upfront,
            // but handle it gracefully rather than losing data. The retry
            // yields a new authorization code, so revoke that one instead:
            // the original was already consumed or has expired.
            let reauthentication = try await ensureFreshAuthentication()
            await revokeAppleTokenIfNeeded(reauthentication)

            do {
                try await gateway.deleteAuthAccount()
            } catch AccountDeletionGatewayError.notAuthenticated {
                throw DeletionError.notAuthenticated
            } catch {
                throw DeletionError.authDeletionFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Remote Deletion

    private func deleteAllUserStorage(userId: String) async throws {
        do {
            try await gateway.deleteAllUserStorage(userId: userId)
        } catch {
            throw DeletionError.storageDeletionFailed(error.localizedDescription)
        }
    }

    /// Deletes legacy flat-path files that predate the user-scoped migration.
    /// Falls back to SwiftData records because the old paths (e.g. `photos/uuid.jpg`)
    /// have no user ID — we can only identify them through the stored download URLs.
    private func deleteLegacyFlatPathMedia(modelContext: ModelContext) async throws {
        let urls: [URL]

        do {
            let workouts = try modelContext.fetch(FetchDescriptor<Workout>())
            urls = workouts.flatMap(\.photos).map(\.url)
        } catch {
            throw DeletionError.storageDeletionFailed(error.localizedDescription)
        }

        guard !urls.isEmpty else { return }
        await gateway.deleteLegacyMedia(at: urls)
    }

    private func deleteLeaderboardStats(userId: String) async throws {
        try await runFirestoreDeletion {
            try await gateway.deleteLeaderboardStats(userId: userId)
        }
    }

    private func deleteFeedbackRateLimitDocument(userId: String) async throws {
        try await runFirestoreDeletion {
            try await gateway.deleteFeedbackRateLimitDocument(userId: userId)
        }
    }

    private func deleteWorkoutBackups(userId: String) async throws {
        try await runFirestoreDeletion {
            try await gateway.deleteWorkoutBackups(userId: userId)
        }
    }

    private func deletePublicProfileMirrors(userId: String) async throws {
        try await runFirestoreDeletion {
            try await gateway.deletePublicProfileMirrors(userId: userId)
        }
    }

    private func deleteUserDocument(userId: String) async throws {
        try await runFirestoreDeletion {
            try await gateway.deleteUserDocument(userId: userId)
        }
    }

    private func runFirestoreDeletion(
        _ deletion: () async throws -> Void
    ) async throws {
        do {
            try await deletion()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DeletionError.firestoreDeletionFailed(error.localizedDescription)
        }
    }

    // MARK: - Local Deletion

    /// Stages local data deletion without saving (allows rollback on failure)
    private func stageLocalDataDeletion(modelContext: ModelContext) throws {
        do {
            let workoutDescriptor = FetchDescriptor<Workout>()
            let workouts = try modelContext.fetch(workoutDescriptor)
            for workout in workouts {
                modelContext.delete(workout)
            }

            let statsDescriptor = FetchDescriptor<LeaderboardStats>()
            let stats = try modelContext.fetch(statsDescriptor)
            for stat in stats {
                modelContext.delete(stat)
            }

            let routineDescriptor = FetchDescriptor<Routine>()
            let routines = try modelContext.fetch(routineDescriptor)
            for routine in routines {
                modelContext.delete(routine)
            }

            let folderDescriptor = FetchDescriptor<RoutineFolder>()
            let folders = try modelContext.fetch(folderDescriptor)
            for folder in folders {
                modelContext.delete(folder)
            }

            let pendingUploadDescriptor = FetchDescriptor<PendingMediaUpload>()
            let pendingUploads = try modelContext.fetch(pendingUploadDescriptor)
            for upload in pendingUploads {
                modelContext.delete(upload)
            }

            let pendingWorkoutDeletionDescriptor = FetchDescriptor<PendingWorkoutDeletion>()
            let pendingWorkoutDeletions = try modelContext.fetch(pendingWorkoutDeletionDescriptor)
            for pendingDeletion in pendingWorkoutDeletions {
                modelContext.delete(pendingDeletion)
            }
        } catch {
            throw DeletionError.localDataDeletionFailed(error.localizedDescription)
        }
    }

    /// Commits staged local deletions to disk
    private func commitStagedLocalDeletion(modelContext: ModelContext) throws {
        do {
            try modelContext.save()
        } catch {
            throw DeletionError.localDataDeletionFailed(error.localizedDescription)
        }
    }

    /// Deletes local pending upload files from disk
    private func clearLocalPendingUploadFiles() async throws {
        do {
            try await localCleanup.clearPendingUploadFiles()
        } catch {
            throw DeletionError.localDataDeletionFailed(error.localizedDescription)
        }
    }

}
