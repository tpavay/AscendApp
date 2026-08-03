import Foundation

struct BlockedClimber: Identifiable, Equatable, Sendable {
    let userId: String
    let createdAt: Date

    var id: String { userId }
}
