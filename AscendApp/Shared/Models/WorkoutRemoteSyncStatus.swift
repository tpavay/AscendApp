import Foundation

enum WorkoutRemoteSyncStatus: String, Codable, Sendable {
    case pendingUpsert
    case synced
    case failed
}
