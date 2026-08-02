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
    func sweepsOnlyOwnerScopedStorageAndNeverTheLegacyFlatPaths() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.reauthenticationResult = .success(
            ReauthenticationResult(appleAuthorizationCode: "apple-auth-code")
        )
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        try await service.deleteAccount(modelContext: try makeModelContext())

        // The root photos/ and videos/ prefixes carry no owner segment, so
        // storage.rules closes them to every client. A sweep aimed there could
        // only ever fail, and reaching for another climber's media is exactly
        // what the closed rules exist to prevent.
        #expect(gateway.steps == [
            .reauthenticate,
            .revokeAppleToken,
            .deleteAllUserStorage,
            .deleteLeaderboardStats,
            .deleteWorkoutBackups,
            .deleteBlockedClimbers,
            .deletePublicProfileMirrors,
            .unregisterPushDevice,
            .deleteUserDocument,
            .deleteAuthAccount,
        ])
    }

    @Test
    func reportsFullProgressOnceEveryStepHasRun() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())

        // totalSteps is hand-maintained, so a step added or removed without
        // updating it leaves the progress bar permanently short or early.
        var lastProgress: AccountDeletionService.DeletionProgress?
        try await service.deleteAccount(modelContext: try makeModelContext()) { progress in
            lastProgress = progress
        }

        let progress = try #require(lastProgress)
        #expect(progress.completedSteps == progress.totalSteps)
        #expect(progress.progressPercentage == 1.0)
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

    // MARK: - Local store sweep

    @Test("Empties every model in the live schema", .bug(id: 348))
    func deletesEveryModelInTheLiveSchema() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())
        let modelContext = try makeModelContext()

        let insertedCounts = try AscendLocalStoreFixture.insertOneOfEach(into: modelContext)
        for (modelName, count) in insertedCounts {
            #expect(count > 0, "Fixture inserted nothing for \(modelName); the sweep would pass vacuously.")
        }

        try await service.deleteAccount(modelContext: modelContext)

        let remainingCounts = try AscendLocalStoreFixture.storedCountsByModelName(in: modelContext)
        for (modelName, count) in remainingCounts {
            #expect(count == 0, "Account deletion left \(count) \(modelName) row(s) on the device.")
        }
    }

    @Test("Empties the derived caches the ownership gate ignores", .bug(id: 348))
    func deletesTheDerivedCachesTheOwnershipGateDoesNotCount() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())
        let modelContext = try makeModelContext()

        try AscendLocalStoreFixture.insertOneOfEach(into: modelContext)

        try await service.deleteAccount(modelContext: modelContext)

        // The gate skips these because a recomputable row is nobody's data. The sweep must not:
        // the two are separate properties, and "delete my account" means the store is empty.
        #expect(!AscendLocalStore.derivedCacheModels.isEmpty)
        for model in AscendLocalStore.derivedCacheModels {
            let modelName = String(describing: model)
            #expect(
                try model.storedCount(in: modelContext) == 0,
                "Account deletion left \(modelName) row(s) on the device."
            )
        }
    }

    @Test("Covers every model in the live schema with a fixture", .bug(id: 348))
    func hasAFixtureForEveryModelInTheLiveSchema() throws {
        // The guard that makes the sweep test stay honest. A model added to the schema with no
        // fixture would leave `deletesEveryModelInTheLiveSchema` asserting 0 == 0 for it forever,
        // which is how four models ended up surviving account deletion unnoticed.
        let uncovered = AscendLocalStoreFixture.liveModelNames
            .subtracting(AscendLocalStoreFixture.coveredModelNames)
            .sorted()

        #expect(
            uncovered.isEmpty,
            """
            \(uncovered.joined(separator: ", ")) is in the live schema with no fixture row. \
            Add one to AscendLocalStoreFixture so deletion is actually proven to remove it.
            """
        )
    }

    @Test("Rolls the whole schema sweep back when the auth deletion fails", .bug(id: 348))
    func rollsBackEveryModelInTheLiveSchemaWhenTheAuthDeletionFails() async throws {
        let gateway = RecordingAccountDeletionGateway()
        gateway.authDeletionError = TestError.remoteFailure
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())
        let modelContext = try makeModelContext()

        let insertedCounts = try AscendLocalStoreFixture.insertOneOfEach(into: modelContext)

        await #expect(throws: AccountDeletionService.DeletionError.self) {
            try await service.deleteAccount(modelContext: modelContext)
        }

        // Widening the sweep must not widen what an aborted deletion destroys.
        let remainingCounts = try AscendLocalStoreFixture.storedCountsByModelName(in: modelContext)
        #expect(remainingCounts == insertedCounts)
    }

    // MARK: - What the next account on this device sees

    @Test("Leaves no completed climbs or resumable session for the next account", .bug(id: 348))
    func leavesNothingForTheNextAccountToClaim() async throws {
        let gateway = RecordingAccountDeletionGateway()
        let service = AccountDeletionService(gateway: gateway, localCleanup: StubLocalCleanup())
        let modelContext = try makeModelContext()

        try AscendLocalStoreFixture.insertOneOfEach(into: modelContext)

        // The deleted account's record, read exactly the way the surfaces that publish it do.
        #expect(ClimbCompletionRepository.completedClimbSet(modelContext: modelContext).completedCount == 1)

        try await service.deleteAccount(modelContext: modelContext)

        // A second account signs in on this device. Deletion cleared the UserDefaults pointer, so
        // the draft store falls back to "most recent draft" - which is only safe because there is
        // no longer a draft to find.
        let nextAccountDefaults = try makeUserDefaults()
        let draftStore = ActiveHeadphoneWorkoutDraftStore(userDefaults: nextAccountDefaults)

        #expect(ClimbCompletionRepository.completedClimbSet(modelContext: modelContext).completedCount == 0)
        #expect(try draftStore.activeDraft(in: modelContext) == nil)
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

    /// Over the live schema, not a hand-listed subset. The subset this replaced was missing
    /// `ActiveHeadphoneWorkoutDraft`, so no test here could have seen the draft survive deletion.
    private func makeModelContext() throws -> ModelContext {
        try AscendLocalStoreFixture.makeModelContext()
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "AccountDeletionServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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
