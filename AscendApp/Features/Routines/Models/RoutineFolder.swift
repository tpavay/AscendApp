import Foundation
import SwiftData

@Model
final class RoutineFolder {
    var id: UUID
    var name: String
    var colorHex: String?
    var order: Int
    var createdAt: Date

    /// When the folder was last edited.
    ///
    /// Optional because folders that already exist have never been edited as
    /// far as the store knows, and stamping them with a made-up date would be a
    /// worse answer than saying so. `effectiveUpdatedAt` reads it.
    var updatedAt: Date?

    // MARK: - Cloud backup state (see `Routine` for why it lives here)

    var ownerUserId: String?
    var lastRemoteSyncAt: Date?
    var lastRemoteSyncError: String?
    var remoteSyncStatusRawValue: String = RoutineRemoteSyncStatus.pendingUpsert.rawValue

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        order: Int = 0
    ) {
        let createdAt = Date()
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.ownerUserId = nil
        self.lastRemoteSyncAt = nil
        self.lastRemoteSyncError = nil
        self.remoteSyncStatusRawValue = RoutineRemoteSyncStatus.pendingUpsert.rawValue
    }

    /// The folder's last-modified stamp, falling back to when it was created.
    var effectiveUpdatedAt: Date {
        updatedAt ?? createdAt
    }

    var remoteSyncStatus: RoutineRemoteSyncStatus {
        get { RoutineRemoteSyncStatus(rawValue: remoteSyncStatusRawValue) ?? .pendingUpsert }
        set { remoteSyncStatusRawValue = newValue.rawValue }
    }

    func markPendingRemoteUpsert(ownerUserId: String, modifiedAt: Date = Date()) {
        self.ownerUserId = ownerUserId
        updatedAt = modifiedAt
        remoteSyncStatus = .pendingUpsert
        lastRemoteSyncError = nil
    }

    func markRemoteSyncSucceeded(syncedAt: Date = Date()) {
        lastRemoteSyncAt = syncedAt
        remoteSyncStatus = .synced
        lastRemoteSyncError = nil
    }

    func markRemoteSyncFailed(_ errorMessage: String) {
        remoteSyncStatus = .failed
        lastRemoteSyncError = errorMessage
    }
}
