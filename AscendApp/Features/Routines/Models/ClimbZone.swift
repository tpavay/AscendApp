import Foundation

enum ClimbZone: String, Codable, CaseIterable, Sendable {
    case recovery
    case warmup
    case easy
    case steady
    case tempo
    case threshold
    case sprint
    case allOut

    var levelOffset: Int {
        switch self {
        case .recovery:
            return -5
        case .warmup:
            return -3
        case .easy:
            return -2
        case .steady:
            return 0
        case .tempo:
            return 2
        case .threshold:
            return 4
        case .sprint:
            return 7
        case .allOut:
            return 10
        }
    }

    var displayName: String {
        switch self {
        case .recovery:
            return "Recovery"
        case .warmup:
            return "Warmup"
        case .easy:
            return "Easy"
        case .steady:
            return "Steady"
        case .tempo:
            return "Tempo"
        case .threshold:
            return "Threshold"
        case .sprint:
            return "Sprint"
        case .allOut:
            return "All Out"
        }
    }
}
