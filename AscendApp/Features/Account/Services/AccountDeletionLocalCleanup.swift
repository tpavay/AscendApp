//
//  AccountDeletionLocalCleanup.swift
//  AscendApp
//

import Foundation

/// The on-device caches and files that must not survive account deletion.
///
/// Separate from `AccountDeletionGateway` because these are process-wide
/// singletons rather than remote calls, and injecting them keeps tests from
/// wiping the test host's UserDefaults and documents directory.
@MainActor
protocol AccountDeletionLocalCleanup {
    func suspendAuthenticatedSessionWork() async
    func resumeAuthenticatedSessionWork()
    func discardAuthenticatedSessionWork()
    func clearPendingUploadFiles() async throws
    func clearUserDefaults()
    func clearImageCache()
}

/// The production cleanup, backed by the app's real storage.
@MainActor
struct AppAccountDeletionLocalCleanup: AccountDeletionLocalCleanup {
    private let userDefaults: UserDefaults
    private let persistentDomainName: String?
    private let settingsManager: SettingsManager
    private let climbDropNotificationState: ClimbDropNotificationState
    private let bootstrapCoordinator: AuthenticatedBootstrapCoordinator
    private let autonomousSessionWorkers: [any AuthenticatedSessionWorker]

    init(
        userDefaults: UserDefaults = .standard,
        persistentDomainName: String? = Bundle.main.bundleIdentifier,
        settingsManager: SettingsManager = .shared,
        climbDropNotificationState: ClimbDropNotificationState = .shared,
        bootstrapCoordinator: AuthenticatedBootstrapCoordinator = .shared,
        autonomousSessionWorkers: [any AuthenticatedSessionWorker] = [
            AppleHealthEnrichmentCoordinator.shared,
            MediaUploadManager.shared
        ]
    ) {
        self.userDefaults = userDefaults
        self.persistentDomainName = persistentDomainName
        self.settingsManager = settingsManager
        self.climbDropNotificationState = climbDropNotificationState
        self.bootstrapCoordinator = bootstrapCoordinator
        self.autonomousSessionWorkers = autonomousSessionWorkers
    }

    /// Quiesces every writer of account-scoped local state, not just the bootstrap chain.
    ///
    /// Apple Health enrichment reaches the same `ModelContext` from outside that chain on its own
    /// schedule, so leaving it running let one write land inside deletion's staged window - which
    /// both saved the staged sweep early and left a row owned by the account being deleted.
    func suspendAuthenticatedSessionWork() async {
        await bootstrapCoordinator.suspendAndDrain(autonomousWorkers: autonomousSessionWorkers)
    }

    func resumeAuthenticatedSessionWork() {
        bootstrapCoordinator.resumeLatest()
    }

    func discardAuthenticatedSessionWork() {
        bootstrapCoordinator.discard()
    }

    func clearPendingUploadFiles() async throws {
        try await LocalMediaStorage.clearAllPendingUploads()
    }

    /// Clears all UserDefaults for the app domain
    func clearUserDefaults() {
        if let persistentDomainName {
            userDefaults.removePersistentDomain(forName: persistentDomainName)
        }

        settingsManager.resetInMemoryAfterAccountDeletion()
        climbDropNotificationState.resetAfterAccountDeletion()
    }

    func clearImageCache() {
        ImageCache.shared.clearAll()
    }
}
