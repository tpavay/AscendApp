import Foundation

/// The first climb a climber chose on the post-sign-in questions of 1.2 and earlier, handed to the
/// first launch that reaches the main app.
///
/// Read only. Nothing writes it any more - the questions are gone - so the one value it can ever
/// hold is one a climber staged on an older build and had not yet carried into the app when they
/// updated. Remove it, and the `MainTabView` call that consumes it, in 1.4.0, when that window has
/// closed.
struct OnboardingFirstClimbHandoffStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func consume(for userId: String) -> String? {
        let key = storageKey(for: userId)
        guard let climbId = userDefaults.string(forKey: key),
              !climbId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        userDefaults.removeObject(forKey: key)
        return climbId
    }

    private func storageKey(for userId: String) -> String {
        "postAuthOnboarding.firstClimbHandoff.v1.\(userId)"
    }
}
