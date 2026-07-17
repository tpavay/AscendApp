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
    func clearPendingUploadFiles() async throws
    func clearUserDefaults()
    func clearImageCache()
}

/// The production cleanup, backed by the app's real storage.
@MainActor
struct AppAccountDeletionLocalCleanup: AccountDeletionLocalCleanup {

    func clearPendingUploadFiles() async throws {
        try await LocalMediaStorage.clearAllPendingUploads()
    }

    /// Clears all UserDefaults for the app domain
    func clearUserDefaults() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
    }

    func clearImageCache() {
        ImageCache.shared.clearAll()
    }
}
