import Foundation

/// Where a user-authored routine or folder stands with its cloud backup.
///
/// Deliberately narrower than `WorkoutRemoteSyncStatus`: a workout can be
/// `rejected` because implausible totals must never reach the backup, while a
/// routine has no equivalent gate - anything the editor can build is legitimate
/// user content. What the server does bound is the shape of the document: the
/// interval ceiling and the name and description lengths. A record past one of
/// those is `rejected` rather than retried forever, because the refusal is
/// permanent and a retry loop would leave it silently unbacked.
enum RoutineRemoteSyncStatus: String, Codable, Sendable {
    case pendingUpsert
    case synced
    case failed
    case rejected
}
