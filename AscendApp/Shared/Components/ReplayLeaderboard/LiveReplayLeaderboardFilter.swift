import Foundation

enum LiveReplayLeaderboardFilter: String, CaseIterable, Identifiable, Sendable {
    case everyone
    case currentUser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone:
            return "Everyone"
        case .currentUser:
            return "Just me"
        }
    }
}
