//
//  AccountDeletionService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftData

/// Service responsible for handling complete account deletion
/// Deletes data from: Firebase Auth, Firestore, Firebase Storage, local SwiftData, and local app caches
@MainActor
final class AccountDeletionService {

    enum DeletionError: LocalizedError {
        case notAuthenticated
        case firestoreDeletionFailed(String)
        case storageDeletionFailed(String)
        case integrationDeletionFailed(String)
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
            case .integrationDeletionFailed(let message):
                return "Failed to disconnect integrations: \(message)"
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

    private let authService = AuthenticationService()
    
    struct DeletionProgress {
        var currentStep: String
        var completedSteps: Int
        var totalSteps: Int
        
        var progressPercentage: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(completedSteps) / Double(totalSteps)
        }
    }
    
    private let db = Firestore.firestore()
    
    /// Performs complete account deletion
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local data deletion
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: True if deletion was successful
    func deleteAccount(
        modelContext: ModelContext,
        progressHandler: ((DeletionProgress) -> Void)? = nil
    ) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DeletionError.notAuthenticated
        }

        let userId = user.uid
        let totalSteps = 10
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
        try await ensureFreshAuthentication(user: user)
        completedSteps += 1
        try Task.checkCancellation()

        // ── From this point on, every step is non-interactive. ──

        // Step 2: Disconnect cloud integrations
        updateProgress("Disconnecting integrations...")
        try await disconnectCloudIntegrations()
        completedSteps += 1
        try Task.checkCancellation()

        // Step 3: Delete all user media from Firebase Storage (storage-level sweep)
        updateProgress("Deleting workout media...")
        try await deleteAllUserMedia(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 4: Delete any legacy flat-path files referenced by local records
        updateProgress("Cleaning up legacy media...")
        try await deleteLegacyFlatPathMedia(modelContext: modelContext)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 5: Delete Firestore leaderboard stats
        updateProgress("Deleting leaderboard data...")
        try await deleteLeaderboardStats(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 6: Delete Firestore rate-limit metadata
        updateProgress("Deleting feedback metadata...")
        try await deleteFeedbackRateLimitDocument(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 7: Delete Firestore user document
        updateProgress("Deleting user profile...")
        try await deleteUserDocument(userId: userId)
        completedSteps += 1
        try Task.checkCancellation()

        // Step 8: Stage local deletion (rollback if auth deletion fails)
        updateProgress("Preparing local data cleanup...")
        try stageLocalDataDeletion(modelContext: modelContext)
        hasStagedLocalDeletion = true
        completedSteps += 1
        try Task.checkCancellation()

        // Step 9: Delete Firebase Auth account (credentials already fresh from Step 1)
        updateProgress("Deleting account...")
        try await deleteAuthAccount()
        completedSteps += 1
        try Task.checkCancellation()

        // Step 10: Commit local deletion and clear caches
        updateProgress("Finalizing local cleanup...")
        try commitStagedLocalDeletion(modelContext: modelContext)
        hasCommittedLocalDeletion = true
        try await clearLocalPendingUploadFiles()
        clearUserDefaults()
        clearLocalIntegrationState()
        ImageCache.shared.clearAll()
        completedSteps += 1

        updateProgress("Account deleted successfully")
    }
    
    // MARK: - Private Deletion Methods

    /// Proactively reauthenticates the user so that the interactive sign-in
    /// happens BEFORE any destructive operations. If the user cancels here,
    /// no data has been deleted yet.
    private func ensureFreshAuthentication(user: User) async throws {
        let providerIDs = user.providerData.map { $0.providerID }

        do {
            if providerIDs.contains("google.com") {
                try await authService.reauthenticateWithGoogle()
            } else if providerIDs.contains("apple.com") {
                try await authService.reauthenticateWithApple()
            } else {
                throw DeletionError.reauthenticationFailed("Unknown sign-in provider")
            }
        } catch is CancellationError {
            throw DeletionError.reauthenticationCancelled
        } catch let error as DeletionError {
            throw error
        } catch {
            throw DeletionError.reauthenticationFailed(error.localizedDescription)
        }
    }

    /// Deletes Firebase Auth account. Credentials should already be fresh
    /// from ensureFreshAuthentication(), but handles requiresRecentLogin
    /// as a fallback just in case.
    private func deleteAuthAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw DeletionError.notAuthenticated
        }

        do {
            try await user.delete()
        } catch let error as NSError {
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                // This shouldn't happen since we reauthenticated upfront,
                // but handle it gracefully rather than losing data.
                let providerIDs = user.providerData.map { $0.providerID }
                try await ensureFreshAuthentication(
                    user: user
                )
                guard let refreshedUser = Auth.auth().currentUser else {
                    throw DeletionError.notAuthenticated
                }
                try await refreshedUser.delete()
            } else {
                throw DeletionError.authDeletionFailed(error.localizedDescription)
            }
        }
    }

    /// Sweeps all user-scoped Storage prefixes and deletes every file.
    /// This is independent of SwiftData — it catches orphaned files too.
    private nonisolated func deleteAllUserMedia(userId: String) async throws {
        let userRoot = Storage.storage().reference()
            .child("users")
            .child(userId)

        let prefixes = [
            userRoot.child("photos"),
            userRoot.child("videos"),
            userRoot.child("profile_pictures"),
        ]

        for prefix in prefixes {
            do {
                try await deleteAllFiles(under: prefix)
            } catch {
                throw DeletionError.storageDeletionFailed(error.localizedDescription)
            }
        }
    }

    /// Deletes legacy flat-path files that predate the user-scoped migration.
    /// Falls back to SwiftData records because the old paths (e.g. `photos/uuid.jpg`)
    /// have no user ID — we can only identify them through the stored download URLs.
    private func deleteLegacyFlatPathMedia(modelContext: ModelContext) async throws {
        let descriptor = FetchDescriptor<Workout>()

        do {
            let workouts = try modelContext.fetch(descriptor)
            let allPhotos = workouts.flatMap(\.photos)

            guard !allPhotos.isEmpty else { return }

            let storage = Storage.storage()
            for photo in allPhotos {
                try Task.checkCancellation()
                do {
                    let ref = try storage.reference(for: photo.url)
                    try await ref.delete()
                } catch let error as NSError
                    where error.domain == StorageErrorDomain &&
                          error.code == StorageErrorCode.objectNotFound.rawValue {
                    // Already deleted (possibly by the user-scoped sweep) — continue
                    continue
                } catch {
                    // Best-effort: log but don't block deletion for legacy files
                    continue
                }
            }
        } catch let error as DeletionError {
            throw error
        } catch {
            throw DeletionError.storageDeletionFailed(error.localizedDescription)
        }
    }

    /// Recursively lists and deletes all files under a Storage reference.
    private nonisolated func deleteAllFiles(under ref: StorageReference) async throws {
        let result: StorageListResult
        do {
            result = try await ref.listAll()
        } catch let error as NSError
            where error.domain == StorageErrorDomain &&
                  error.code == StorageErrorCode.objectNotFound.rawValue {
            // Prefix doesn't exist — nothing to delete
            return
        }

        for item in result.items {
            do {
                try await item.delete()
            } catch let error as NSError
                where error.domain == StorageErrorDomain &&
                      error.code == StorageErrorCode.objectNotFound.rawValue {
                continue
            }
        }

        for prefix in result.prefixes {
            try await deleteAllFiles(under: prefix)
        }
    }

    /// Deletes all leaderboard stats documents for the user from Firestore
    private func deleteLeaderboardStats(userId: String) async throws {
        do {
            let query = db.collection("leaderboard_stats")
                .whereField("userId", isEqualTo: userId)

            let snapshot = try await query.getDocuments()

            for document in snapshot.documents {
                try await document.reference.delete()
            }
        } catch {
            throw DeletionError.firestoreDeletionFailed(error.localizedDescription)
        }
    }

    /// Deletes user rate-limit metadata stored in Firestore
    private func deleteFeedbackRateLimitDocument(userId: String) async throws {
        do {
            try await db.collection("userRateLimits").document(userId).delete()
        } catch {
            throw DeletionError.firestoreDeletionFailed(error.localizedDescription)
        }
    }

    /// Disconnects cloud integrations before auth account deletion
    private func disconnectCloudIntegrations() async throws {
        do {
            try await StravaManager.shared.disconnect()
        } catch StravaError.notConnected {
            // Already disconnected
        } catch {
            throw DeletionError.integrationDeletionFailed(error.localizedDescription)
        }
    }

    /// Deletes the user document from Firestore
    private func deleteUserDocument(userId: String) async throws {
        do {
            try await db.collection("users").document(userId).delete()
        } catch {
            throw DeletionError.firestoreDeletionFailed(error.localizedDescription)
        }
    }

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

            let recordsDescriptor = FetchDescriptor<PersonalRecord>()
            let records = try modelContext.fetch(recordsDescriptor)
            for record in records {
                modelContext.delete(record)
            }

            let goalsDescriptor = FetchDescriptor<Goal>()
            let goals = try modelContext.fetch(goalsDescriptor)
            for goal in goals {
                modelContext.delete(goal)
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

            let weightPRDescriptor = FetchDescriptor<WeightPersonalRecord>()
            let weightPRs = try modelContext.fetch(weightPRDescriptor)
            for weightPR in weightPRs {
                modelContext.delete(weightPR)
            }

            let aggregateWeightDescriptor = FetchDescriptor<AggregateWeightRecord>()
            let aggregateWeightRecords = try modelContext.fetch(aggregateWeightDescriptor)
            for aggregateRecord in aggregateWeightRecords {
                modelContext.delete(aggregateRecord)
            }

            let pendingUploadDescriptor = FetchDescriptor<PendingMediaUpload>()
            let pendingUploads = try modelContext.fetch(pendingUploadDescriptor)
            for upload in pendingUploads {
                modelContext.delete(upload)
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
            try await LocalMediaStorage.clearAllPendingUploads()
        } catch {
            throw DeletionError.localDataDeletionFailed(error.localizedDescription)
        }
    }

    /// Clears all UserDefaults for the app domain
    private func clearUserDefaults() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        UserDefaults.standard.synchronize()
    }

    /// Clears local integration state (Keychain/UserDefaults cache)
    private func clearLocalIntegrationState() {
        HevyManager.shared.disconnect()
        StravaManager.shared.clearLocalState()
    }
}
