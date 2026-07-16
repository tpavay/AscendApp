import Foundation

struct ProfileHeadToHeadClimbResult: Identifiable, Equatable {
    enum Winner: Equatable {
        case viewer
        case otherUser
        case tie
    }

    let id: String
    let climbName: String
    let stepCount: Int
    let viewerDurationSeconds: TimeInterval
    let otherUserDurationSeconds: TimeInterval
    let mostRecentAt: Date
    let winner: Winner
}
