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
            !LandingScreenActionLayoutPolicy.usesCompactSignInLabel(
                for: .xxxLarge
            )
        )
        #expect(LandingScreenActionLayoutPolicy.signInTitle == "Sign in")
        #expect(
            LandingScreenActionLayoutPolicy.signInAccessibilityLabel
                == "Already have an account? Sign in"
        )
    }

    @Test
    func bottomActionsHaveBoundedContentHeight() {
        #expect(
            LandingScreenActionLayoutPolicy.maximumBottomContentHeight == 116
        )
    }
}
