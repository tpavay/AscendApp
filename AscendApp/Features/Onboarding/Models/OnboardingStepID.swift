import Foundation

enum OnboardingStepID: String, Codable, CaseIterable {
    case welcome
    case healthKit
    case measurementSystem
    case fitnessLevel
    case personalDetails
    case bodyMetrics
    case location
    case notifications
    case auth

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var progressValue: Double {
        let total = max(Self.allCases.count - 1, 1)
        return Double(index + 1) / Double(total)
    }

    var isFinalStep: Bool {
        self == .auth
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome:
            return "Get Started"
        default:
            return "Continue"
        }
    }
}
