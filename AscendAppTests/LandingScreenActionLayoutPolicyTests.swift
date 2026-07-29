import SwiftUI
import Testing
@testable import AscendApp

struct LandingScreenActionLayoutPolicyTests {
    @Test
    func accessibilitySizesUseCompactVisibleSignInCopy() {
        #expect(
            LandingScreenActionLayoutPolicy.usesCompactSignInLabel(
                for: .accessibility1
            )
        )
        #expect(
            LandingScreenActionLayoutPolicy.usesCompactSignInLabel(
                for: .accessibility5
            )
        )
        #expect(
            LandingScreenActionLayoutPolicy.usesCompactSignInLabel(
                for: .xxxLarge
            ) == false
        )
        #expect(LandingScreenActionLayoutPolicy.signInTitle == "Sign in")
        #expect(
            LandingScreenActionLayoutPolicy.signInAccessibilityLabel
                == "Already have an account? Sign in"
        )
    }

    @Test
    func bottomActionsPreserveMinimumTouchTargets() {
        #expect(LandingScreenActionLayoutPolicy.primaryActionHeight >= 44)
        #expect(LandingScreenActionLayoutPolicy.secondaryActionMinimumHeight >= 44)
        #expect(LandingScreenActionLayoutPolicy.minimumBottomContentHeight == 116)
    }
}
