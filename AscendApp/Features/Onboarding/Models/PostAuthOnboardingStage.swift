import Foundation

enum PostAuthOnboardingStage: String, CaseIterable, Codable, Identifiable {
    case displayName

    static var allCases: [PostAuthOnboardingStage] {
        [
            .displayName
        ]
    }

    var id: String { rawValue }

    var next: PostAuthOnboardingStage? {
        let stages = Self.allCases
        guard let currentIndex = stages.firstIndex(of: self) else { return nil }
        let nextIndex = stages.index(after: currentIndex)
        return nextIndex < stages.endIndex ? stages[nextIndex] : nil
    }

    var progressIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static var first: PostAuthOnboardingStage {
        .displayName
    }
}

enum PostAuthOnboardingPhase: Equatable {
    case signedOut
    case resolving
    case onboarding(PostAuthOnboardingStage)
    case complete
}

extension Notification.Name {
    static let postAuthOnboardingStateDidChange = Notification.Name("postAuthOnboardingStateDidChange")
}
