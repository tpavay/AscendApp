import Foundation

/// How intensity is specified for an interval
enum IntensityType: String, Codable, CaseIterable, Sendable {
    case level
    case stepsPerMinute

    var displayName: String {
        switch self {
        case .level:
            return "Level"
        case .stepsPerMinute:
            return "Steps/Min"
        }
    }

    var shortName: String {
        switch self {
        case .level:
            return "Lvl"
        case .stepsPerMinute:
            return "SPM"
        }
    }
}

/// Direction for sideways climbing
enum SidewaysDirection: String, Codable, CaseIterable, Sendable {
    case left
    case right

    var displayName: String {
        switch self {
        case .left:
            return "Face Left"
        case .right:
            return "Face Right"
        }
    }

    var shortName: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}

/// Modifiers that can be applied during an interval
struct IntervalModifiers: Codable, Equatable, Sendable {
    var sidewaysDirection: SidewaysDirection? = nil
    var skipStep: Bool = false
    var backwardStep: Bool = false
    var holdingBars: Bool = false
    var weightOverride: IntervalWeightOverride? = nil

    var activeModifiers: [String] {
        var result: [String] = []
        if let direction = sidewaysDirection {
            result.append(direction == .left ? "Facing Left" : "Facing Right")
        }
        if skipStep { result.append("Skip Step") }
        if backwardStep { result.append("Backward") }
        if holdingBars { result.append("Holding Bars") }
        if let override = weightOverride, !override.usesRoutineDefaults {
            if let types = override.enabledEquipmentTypes, !types.isEmpty {
                result.append("Custom Weights")
            } else {
                result.append("No Weights")
            }
        }
        return result
    }

    var hasAnyActive: Bool {
        sidewaysDirection != nil || skipStep || backwardStep || holdingBars || hasWeightOverride
    }

    var stepTypeDescription: String {
        var labels: [String] = []

        if let direction = sidewaysDirection {
            labels.append(direction == .left ? "Face left" : "Face right")
        }

        if skipStep {
            labels.append("Skip step")
        }

        if backwardStep {
            labels.append("Backward step")
        }

        if labels.isEmpty {
            return "Standard step"
        }

        return labels.joined(separator: " · ")
    }

    /// Whether this interval has a weight override (not using routine defaults)
    var hasWeightOverride: Bool {
        guard let override = weightOverride else { return false }
        return !override.usesRoutineDefaults
    }

    static let none = IntervalModifiers()
    static let standard = IntervalModifiers()
    static let skipStep = IntervalModifiers(skipStep: true)
    static let backward = IntervalModifiers(backwardStep: true)

    static func facing(_ direction: SidewaysDirection) -> IntervalModifiers {
        IntervalModifiers(sidewaysDirection: direction)
    }

    // Convenience initializer for backward compatibility
    init(
        sidewaysDirection: SidewaysDirection? = nil,
        skipStep: Bool = false,
        backwardStep: Bool = false,
        holdingBars: Bool = false,
        weightOverride: IntervalWeightOverride? = nil
    ) {
        self.sidewaysDirection = sidewaysDirection
        self.skipStep = skipStep
        self.backwardStep = backwardStep
        self.holdingBars = holdingBars
        self.weightOverride = weightOverride
    }
}

/// Source of a routine (built-in vs user-created)
enum RoutineSource: String, Codable, Sendable {
    case builtin
    case remoteTemplate
    case userCreated
    case copiedFromBuiltin

    var displayName: String {
        switch self {
        case .builtin:
            return "Built-in"
        case .remoteTemplate:
            return "Ascend Routine"
        case .userCreated:
            return "My Routine"
        case .copiedFromBuiltin:
            return "Customized"
        }
    }

    var isTemplate: Bool {
        switch self {
        case .builtin, .remoteTemplate:
            return true
        case .userCreated, .copiedFromBuiltin:
            return false
        }
    }
}

/// Completion status of a routine-based workout
enum RoutineCompletionStatus: String, Codable, Sendable {
    case completed
    case stoppedEarly

    var displayName: String {
        switch self {
        case .completed:
            return "Completed"
        case .stoppedEarly:
            return "Stopped Early"
        }
    }
}
