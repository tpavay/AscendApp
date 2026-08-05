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
    private let bootstrapCoordinator: AuthenticatedBootstrapCoordinator

    init(
        userDefaults: UserDefaults = .standard,
        persistentDomainName: String? = Bundle.main.bundleIdentifier,
        settingsManager: SettingsManager = .shared,
        bootstrapCoordinator: AuthenticatedBootstrapCoordinator = .shared
    ) {
        self.userDefaults = userDefaults
        self.persistentDomainName = persistentDomainName
        self.settingsManager = settingsManager
        self.bootstrapCoordinator = bootstrapCoordinator
    }

    func suspendAuthenticatedSessionWork() async {
        await bootstrapCoordinator.suspendAndDrain()
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
    }

    func clearImageCache() {
        ImageCache.shared.clearAll()
    }
}
