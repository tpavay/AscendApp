#if DEBUG
import Foundation

enum JourneyStepStatus {
    case completed
    case current
    case locked

    var label: String {
        switch self {
        case .completed:
            "Claimed"
        case .current:
            "Next"
        case .locked:
            "Locked"
        }
    }

    var systemImageName: String {
        switch self {
        case .completed:
            "checkmark"
        case .current:
            "figure.stairs"
        case .locked:
            "lock.fill"
        }
    }
}
#endif
