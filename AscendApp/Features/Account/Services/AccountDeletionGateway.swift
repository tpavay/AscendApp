//
//  AccountDeletionGateway.swift
//  AscendApp
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// The remote (Firebase) side effects of deleting an account.
///
/// `AccountDeletionService` owns the *order* these run in, which is the part
/// that matters for App Store guideline 5.1.1(v) and the part worth testing.
/// Keeping the Firebase calls behind this protocol lets the sequence be
/// verified without standing up Firebase.
@MainActor
protocol AccountDeletionGateway {
    /// The signed-in user's uid, or nil when nobody is signed in.
    var currentUserId: String? { get }

    /// Reauthenticates the signed-in user with whichever provider they used.
    func reauthenticate() async throws -> ReauthenticationResult

    func deleteAllUserStorage(userId: String) async throws

    /// Best-effort deletion of legacy flat-path media identified by download URL.
    func deleteLegacyMedia(at urls: [URL]) async

    func deleteLeaderboardStats(userId: String) async throws
    func deleteWorkoutBackups(userId: String) async throws
    func deleteBlockedClimbers(userId: String) async throws

    /// Deletes the publicly readable mirrors of the user's profile.
    func deletePublicProfileMirrors(userId: String) async throws

    /// Best-effort deactivation of the user's push delivery records.
    func unregisterPushDevice() async

    func deleteUserDocument(userId: String) async throws
    func revokeAppleToken(authorizationCode: String) async throws
    func deleteAuthAccount() async throws
}

/// Errors the gateway raises that the service maps onto `DeletionError`.
enum AccountDeletionGatewayError: Error {
    case notAuthenticated
    case unknownProvider
}

/// The provider a user reauthenticates with before their account is deleted.
enum AccountDeletionReauthenticationProvider: Equatable {
    case apple
    case google

    /// Picks which linked provider to reauthenticate with.
    ///
    /// Apple wins whenever it is linked, even when Google is linked too: the
    /// authorization code that Sign in with Apple revocation needs is only ever
    /// produced by an Apple authorization, so reauthenticating a multi-provider
    /// uid with Google would silently skip the revocation guideline 5.1.1(v)
    /// requires. Firebase's "link accounts that use the same email" setting
    /// produces those uids without any linking code in the app.
    static func preferred(forProviderIDs providerIDs: [String]) -> Self? {
        if providerIDs.contains("apple.com") {
            return .apple
        }

        if providerIDs.contains("google.com") {
            return .google
        }

        return nil
    }
}

/// The production gateway, backed by Firebase Auth, Firestore, and Storage.
@MainActor
struct FirebaseAccountDeletionGateway: AccountDeletionGateway {

    private let authService: AuthenticationService

    init(authService: AuthenticationService = AuthenticationService()) {
        self.authService = authService
    }

    private var db: Firestore { Firestore.firestore() }

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    func reauthenticate() async throws -> ReauthenticationResult {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionGatewayError.notAuthenticated
        }

        let provider = AccountDeletionReauthenticationProvider.preferred(
            forProviderIDs: user.providerData.map(\.providerID)
        )

        switch provider {
        case .apple:
            return try await authService.reauthenticateWithApple()
        case .google:
            return try await authService.reauthenticateWithGoogle()
        case nil:
            throw AccountDeletionGatewayError.unknownProvider
        }
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        try await authService.revokeAppleToken(authorizationCode: authorizationCode)
    }

    func unregisterPushDevice() async {
        await PushNotificationService.shared.unregisterCurrentDevice()
    }

    func deleteAuthAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionGatewayError.notAuthenticated
        }
        try await user.delete()
    }

    // MARK: - Storage

    // StorageReference is not Sendable, so every reference is created and
    // consumed inside these nonisolated helpers. Only Sendable values (the uid,
    // the legacy URLs) cross the actor boundary.

    /// Sweeps all user-scoped Storage prefixes and deletes every file.
    /// This is independent of SwiftData — it catches orphaned files too.
    func deleteAllUserStorage(userId: String) async throws {
        try await Self.sweepUserStorage(userId: userId)
    }

    func deleteLegacyMedia(at urls: [URL]) async {
        await Self.sweepLegacyMedia(at: urls)
    }

    private nonisolated static func sweepUserStorage(userId: String) async throws {
        let userRoot = Storage.storage().reference()
            .child("users")
            .child(userId)

        let prefixes = [
            userRoot.child("photos"),
            userRoot.child("videos"),
            userRoot.child("profile_pictures"),
            userRoot.child("workout_heart_rate"),
        ]

        for prefix in prefixes {
            try await deleteAllFiles(under: prefix)
        }
    }

    private nonisolated static func sweepLegacyMedia(at urls: [URL]) async {
        let storage = Storage.storage()

        for url in urls {
            if Task.isCancelled { return }
            do {
                let ref = try storage.reference(for: url)
                try await ref.delete()
            } catch {
                // Best-effort: these predate user-scoped paths and may already
                // be gone via the prefix sweep. Never block deletion on them.
                continue
            }
        }
    }

    /// Recursively lists and deletes all files under a Storage reference.
    private nonisolated static func deleteAllFiles(under ref: StorageReference) async throws {
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

    // MARK: - Firestore

    func deleteLeaderboardStats(userId: String) async throws {
        let snapshot = try await db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        for document in snapshot.documents {
            try await document.reference.delete()
        }
    }

    func deleteWorkoutBackups(userId: String) async throws {
        try await deleteAllDocuments(in: userDocument(userId).collection("workouts"))
    }

    func deleteBlockedClimbers(userId: String) async throws {
        try await deleteAllDocuments(in: userDocument(userId).collection("blocked"))
    }

    /// Deletes the publicly readable mirrors of the user's profile.
    ///
    /// `achievements` is deliberately absent: it is server-owned
    /// (`allow write: if false` in firestore.rules), so a client delete would be
    /// rejected. The `cleanupDeletedUserData` Cloud Function sweeps it, along
    /// with every other server-owned subcollection, once the user document goes.
    func deletePublicProfileMirrors(userId: String) async throws {
        let userDocument = userDocument(userId)

        try await userDocument.collection("public_profile").document("current").delete()
        try await userDocument.collection("profile_stats").document("current").delete()
        try await deleteAllDocuments(in: userDocument.collection("profile_workouts"))
    }

    func deleteUserDocument(userId: String) async throws {
        try await userDocument(userId).delete()
    }

    private func userDocument(_ userId: String) -> DocumentReference {
        db.collection("users").document(userId)
    }

    /// Deletes every document in a collection, committing in batches because
    /// Firestore caps a batch at 500 writes.
    private func deleteAllDocuments(in collection: CollectionReference) async throws {
        let snapshot = try await collection.getDocuments()
        guard !snapshot.documents.isEmpty else { return }

        let batchLimit = 500
        var batch = db.batch()
        var operationsInBatch = 0

        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
            operationsInBatch += 1

            if operationsInBatch == batchLimit {
                try await batch.commit()
                batch = db.batch()
                operationsInBatch = 0
            }
        }

        if operationsInBatch > 0 {
            try await batch.commit()
        }
    }
}
