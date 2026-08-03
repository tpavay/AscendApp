import Foundation
import SwiftData

/// Which collection a queued routine deletion targets.
enum PendingRoutineDeletionKind: String, Codable, Sendable {
    case routine
    case folder
}

/// A routine or folder the climber deleted locally whose cloud backup still
/// has to go.
///
/// It is a record of its own rather than a flag on the routine for the same
/// reason `PendingWorkoutDeletion` is: the local row is gone the moment the
/// climber deletes it, and the work of removing the remote copy outlives it.
/// Without this the delete would only ever be local, and the next hydration on
/// any device would restore what the climber just threw away.
@Model
final class PendingRoutineDeletion {
    var id: UUID
    var recordId: UUID
    var kindRawValue: String
    var ownerUserId: String
    var enqueuedAt: Date
    var retryCount: Int
    var lastError: String?

    init(
        recordId: UUID,
        kind: PendingRoutineDeletionKind,
        ownerUserId: String,
        enqueuedAt: Date = Date()
    ) {
        self.id = UUID()
        self.recordId = recordId
        self.kindRawValue = kind.rawValue
        self.ownerUserId = ownerUserId
        self.enqueuedAt = enqueuedAt
        self.retryCount = 0
        self.lastError = nil
    }

    var kind: PendingRoutineDeletionKind {
        get { PendingRoutineDeletionKind(rawValue: kindRawValue) ?? .routine }
        set { kindRawValue = newValue.rawValue }
    }

    func recordFailure(_ message: String) {
        retryCount += 1
        lastError = message
    }
}
