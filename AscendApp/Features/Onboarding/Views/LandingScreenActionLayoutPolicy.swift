import SwiftUI

enum LandingScreenActionLayoutPolicy {
    static let primaryActionHeight: CGFloat = 56
    static let secondaryActionHeight: CGFloat = 44
    static let actionSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 8

    static let signInPrompt = "Already have an account?"
    static let signInTitle = "Sign in"
    static let signInAccessibilityLabel = "\(signInPrompt) \(signInTitle)"

    static var maximumBottomContentHeight: CGFloat {
        primaryActionHeight
            + actionSpacing
            + secondaryActionHeight
            + bottomPadding
    }

    static func usesCompactSignInLabel(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}
