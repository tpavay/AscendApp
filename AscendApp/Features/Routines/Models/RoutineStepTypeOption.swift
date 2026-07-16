import Foundation

enum RoutineStepTypeOption: String, CaseIterable, Identifiable {
    case standard
    case skipStep
    case backward
    case faceLeft
    case faceRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .skipStep:
            return "Skip step"
        case .backward:
            return "Backward"
        case .faceLeft:
            return "Face left"
        case .faceRight:
            return "Face right"
        }
    }

    var modifiers: IntervalModifiers {
        switch self {
        case .standard:
            return .standard
        case .skipStep:
            return .skipStep
        case .backward:
            return .backward
        case .faceLeft:
            return .facing(.left)
        case .faceRight:
            return .facing(.right)
        }
    }

    static func from(modifiers: IntervalModifiers) -> RoutineStepTypeOption {
        if let sidewaysDirection = modifiers.sidewaysDirection {
            return sidewaysDirection == .left ? .faceLeft : .faceRight
        }
        if modifiers.skipStep {
            return .skipStep
        }
        if modifiers.backwardStep {
            return .backward
        }
        return .standard
    }
}
