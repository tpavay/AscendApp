import SwiftUI

enum LandingScreenActionLayoutPolicy {
    static let primaryActionHeight: CGFloat = 56
    static let secondaryActionMinimumHeight: CGFloat = 44
    static let actionSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 8

    static let signInPrompt = "Already have an account?"
    static let signInTitle = "Sign in"
    static let signInAccessibilityLabel = "\(signInPrompt) \(signInTitle)"

    static var minimumBottomContentHeight: CGFloat {
        primaryActionHeight
            + actionSpacing
            + secondaryActionMinimumHeight
            + bottomPadding
    }

    static func usesCompactSignInLabel(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}
