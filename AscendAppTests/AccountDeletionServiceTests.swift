import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct AccountDeletionServiceTests {

    // MARK: - Deletion ordering

    @Test
    func deletesPublicProfileMirrorsBeforeTheAuthAccount() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        let mirrorsIndex = try #require(gateway.steps.firstIndex(of: .deletePublicProfileMirrors))
        let authIndex = try #require(gateway.steps.firstIndex(of: .deleteAuthAccount))

        // firestore.rules gates the mirror deletes on isOwner(userId). Once the
        // auth user is gone, nothing can ever authenticate as that uid again and
        // the mirrors are orphaned PII.
        #expect(mirrorsIndex < authIndex)
    }

    @Test
    func deletesEveryRemoteRecordBeforeTheAuthAccount() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        let authIndex = try #require(gateway.steps.firstIndex(of: .deleteAuthAccount))
        let ownerGatedSteps: [RecordingAccountDeletionGateway.Step] = [
            .deleteAllUserStorage,
            .deleteLeaderboardStats,
            .deleteWorkoutBackups,
            .deleteBlockedClimbers,
            .deletePublicProfileMirrors,
            .deleteUserDocument,
        ]

        for step in ownerGatedSteps {
            let index = try #require(
                gateway.steps.firstIndex(of: step),
                "Expected account deletion to run \(step)."
            )
            #expect(index < authIndex, "Expected \(step) to run before the auth account is deleted.")
        }
    }

    @Test("Unregisters push delivery before deleting the user", .bug(id: 197))
    func unregistersPushDeviceBeforeDeletingTheUser() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        let unregisterIndex = try #require(gateway.steps.firstIndex(of: .unregisterPushDevice))
        let userDocumentIndex = try #require(gateway.steps.firstIndex(of: .deleteUserDocument))
        let authIndex = try #require(gateway.steps.firstIndex(of: .deleteAuthAccount))

        #expect(unregisterIndex < userDocumentIndex)
        #expect(unregisterIndex < authIndex)
    }

    @Test
    func deletesTheUserDocumentLastSoTheServerSweepSeesTheRestGone() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        // Deleting users/{uid} fires cleanupDeletedUserData. Running it after the
        // client's own Firestore deletes keeps the server sweep to the
        // server-owned leftovers rather than racing the client.
        let mirrorsIndex = try #require(gateway.steps.firstIndex(of: .deletePublicProfileMirrors))
        let userDocumentIndex = try #require(gateway.steps.firstIndex(of: .deleteUserDocument))

        #expect(mirrorsIndex < userDocumentIndex)
    }

    @Test
    func reauthenticatesBeforeAnythingIsDeleted() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        #expect(gateway.steps.first == .reauthenticate)
    }

    @Test
    func cancellingReauthenticationDeletesNothing() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.reauthenticationResult = .failure(CancellationError())
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        await #expect(throws: AccountDeletionService.DeletionError.self) {
            try await service.deleteAccount(modelContext: try makeModelContext())
        }

        #expect(gateway.steps == [.reauthenticate])
    }

    @Test
    func keepsLocalDataWhenTheAuthDeletionFails() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.authDeletionError = TestError.remoteFailure
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        let modelContext = try makeModelContext()
        modelContext.insert(Routine(name: "Local Routine"))
        try modelContext.save()

        await #expect(throws: AccountDeletionService.DeletionError.self) {
            try await service.deleteAccount(modelContext: modelContext)
        }

        let routines = try modelContext.fetch(FetchDescriptor<Routine>())
        #expect(routines.count == 1, "Expected staged local deletion to roll back.")
    }

    // MARK: - Sign in with Apple token revocation

    @Test
    func revokesTheAppleTokenBeforeTheStorageSweepAndAuthDeletion() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.reauthenticationResult = .success(
            ReauthenticationResult(appleAuthorizationCode: "apple-auth-code")
        )
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        #expect(gateway.revokedAuthorizationCodes == ["apple-auth-code"])

        // Apple authorization codes expire in ~5 minutes, so revocation runs
        // right after reauth — before the sequential Storage sweep and every
        // later delete — rather than letting the sweep age the code out.
        let revokeIndex = try #require(gateway.steps.firstIndex(of: .revokeAppleToken))
        let storageIndex = try #require(gateway.steps.firstIndex(of: .deleteAllUserStorage))
        let authIndex = try #require(gateway.steps.firstIndex(of: .deleteAuthAccount))
        #expect(revokeIndex < storageIndex)
        #expect(revokeIndex < authIndex)
    }

    @Test
    func skipsRevocationForProvidersWithoutAnAppleAuthorizationCode() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.reauthenticationResult = .success(
            ReauthenticationResult(appleAuthorizationCode: nil)
        )
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        #expect(gateway.revokedAuthorizationCodes.isEmpty)
        #expect(!gateway.steps.contains(.revokeAppleToken))
    }

    @Test
    func completesDeletionWhenAppleTokenRevocationFails() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.reauthenticationResult = .success(
            ReauthenticationResult(appleAuthorizationCode: "apple-auth-code")
        )
        gateway.revocationError = TestError.remoteFailure
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        // A failed revocation must not strand the user with an account they
        // cannot delete, which breaks 5.1.1(v) harder than a lingering token.
        try await service.deleteAccount(modelContext: try makeModelContext())

        #expect(gateway.steps.contains(.deleteAuthAccount))
    }

    // MARK: - Reauthentication provider selection

    @Test
    func reauthenticatesWithAppleWhenBothProvidersAreLinked() async throws {
        // Firebase links same-email providers onto one uid on its own. Only an
        // Apple authorization yields the code revocation needs, so picking
        // Google here would silently skip revocation for that cohort.
        let provider = AccountDeletionReauthenticationProvider.preferred(
            forProviderIDs: ["google.com", "apple.com"]
        )

        #expect(provider == .apple)
    }

    @Test
    func reauthenticatesWithApplePreferringItOverEveryOtherProvider() async throws {
        let provider = AccountDeletionReauthenticationProvider.preferred(
            forProviderIDs: ["apple.com"]
        )

        #expect(provider == .apple)
    }

    @Test
    func reauthenticatesWithGoogleWhenAppleIsNotLinked() async throws {
        let provider = AccountDeletionReauthenticationProvider.preferred(
            forProviderIDs: ["google.com"]
        )

        #expect(provider == .google)
    }

    @Test
    func hasNoProviderToReauthenticateWithWhenNoneIsSupported() async throws {
        let provider = AccountDeletionReauthenticationProvider.preferred(
            forProviderIDs: ["password"]
        )

        #expect(provider == nil)
    }

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            LeaderboardStats.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            PendingMediaUpload.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}

private enum TestError: Error {
    case remoteFailure
}

/// Keeps the tests off the test host's UserDefaults, documents directory, and
/// shared image cache.
@MainActor
private struct StubLocalCleanup: AccountDeletionLocalCleanup {
    func clearPendingUploadFiles() async throws {}
    func clearUserDefaults() {}
    func clearImageCache() {}
}

/// Records the remote deletion steps in the order the service runs them.
@MainActor
private final class RecordingAccountDeletionGateway: AccountDeletionGateway {

    enum Step: Equatable {
        case reauthenticate
        case deleteAllUserStorage
        case deleteLegacyMedia
        case deleteLeaderboardStats
        case deleteWorkoutBackups
        case deleteBlockedClimbers
        case deletePublicProfileMirrors
        case unregisterPushDevice
        case deleteUserDocument
        case revokeAppleToken
        case deleteAuthAccount
    }

    private(set) var steps: [Step] = []
    private(set) var revokedAuthorizationCodes: [String] = []

    var currentUserId: String? = "user-a"
    var reauthenticationResult: Result<ReauthenticationResult, Error> =
        .success(ReauthenticationResult(appleAuthorizationCode: nil))
    var revocationError: Error?
    var authDeletionError: Error?

    func reauthenticate() async throws -> ReauthenticationResult {
        steps.append(.reauthenticate)
        return try reauthenticationResult.get()
    }

    func deleteAllUserStorage(userId: String) async throws {
        steps.append(.deleteAllUserStorage)
    }

    func deleteLegacyMedia(at urls: [URL]) async {
        steps.append(.deleteLegacyMedia)
    }

    func deleteLeaderboardStats(userId: String) async throws {
        steps.append(.deleteLeaderboardStats)
    }

    func deleteWorkoutBackups(userId: String) async throws {
        steps.append(.deleteWorkoutBackups)
    }

    func deleteBlockedClimbers(userId: String) async throws {
        steps.append(.deleteBlockedClimbers)
    }

    func deletePublicProfileMirrors(userId: String) async throws {
        steps.append(.deletePublicProfileMirrors)
    }

    func unregisterPushDevice() async {
        steps.append(.unregisterPushDevice)
    }

    func deleteUserDocument(userId: String) async throws {
        steps.append(.deleteUserDocument)
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        steps.append(.revokeAppleToken)
        if let revocationError {
            throw revocationError
        }
        revokedAuthorizationCodes.append(authorizationCode)
    }

    func deleteAuthAccount() async throws {
        steps.append(.deleteAuthAccount)
        if let authDeletionError {
            throw authDeletionError
        }
    }
}
