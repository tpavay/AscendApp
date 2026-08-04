import Foundation

enum IntensityTier: String, CaseIterable, Codable, Sendable {
    case minimal
    case light
    case moderate
    case high
    case maximum

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .maximum: return "Maximum"
        }
    }

    var description: String {
        switch self {
        case .minimal:
            return "Gentle, recovery-focused climbing below your steady pace."
        case .light:
            return "Comfortable climbing you can settle into for an easy session."
        case .moderate:
            return "Your sustainable steady effort for longer climbs."
        case .high:
            return "Hard climbing above baseline that takes focus to hold."
        case .maximum:
            return "Very hard work reserved for short, near-max pushes."
        }
    }

    var heatMapScore: Double {
        switch self {
        case .minimal: return 0.1
        case .light: return 0.3
        case .moderate: return 0.5
        case .high: return 0.7
        case .maximum: return 0.9
        }
    }

    static func from(score: Double) -> IntensityTier {
        switch score {
        case ..<0.2:
            return .minimal
        case ..<0.4:
            return .light
        case ..<0.6:
            return .moderate
        case ..<0.8:
            return .high
        default:
            return .maximum
        }
    }
}
