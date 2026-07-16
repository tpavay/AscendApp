import Foundation
import SwiftData

@Model
final class PendingWorkoutDeletion {
    var id: UUID
    var workoutId: UUID
    var ownerUserId: String
    var enqueuedAt: Date
    var retryCount: Int
    var lastError: String?

    init(
        workoutId: UUID,
        ownerUserId: String,
        enqueuedAt: Date = Date()
    ) {
        self.id = UUID()
        self.workoutId = workoutId
        self.ownerUserId = ownerUserId
        self.enqueuedAt = enqueuedAt
        self.retryCount = 0
        self.lastError = nil
    }

    func recordFailure(_ message: String) {
        retryCount += 1
        lastError = message
    }
}
