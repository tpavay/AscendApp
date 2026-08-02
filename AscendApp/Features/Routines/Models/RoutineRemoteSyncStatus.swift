import Foundation

/// Where a user-authored routine or folder stands with its cloud backup.
///
/// Deliberately narrower than `WorkoutRemoteSyncStatus`: a workout can be
/// `rejected` because implausible totals must never reach the backup, while a
/// routine has no equivalent gate - anything the editor can build is legitimate
/// user content. The one bound the server enforces is the interval ceiling, and
/// a routine past it is `rejected` rather than retried forever.
enum RoutineRemoteSyncStatus: String, Codable, Sendable {
    case pendingUpsert
    case synced
    case failed
    case rejected
}
