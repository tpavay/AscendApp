import Foundation

enum ClimbReleaseState: String, Codable, CaseIterable, Sendable {
    case available
    case comingSoon
    case hidden
    case disabled

    var isAvailable: Bool {
        self == .available
    }

    var isVisibleOnGlobe: Bool {
        switch self {
        case .available, .comingSoon:
            return true
        case .hidden, .disabled:
            return false
        }
    }
}
