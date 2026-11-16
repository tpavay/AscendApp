import AuthenticationServices
import Testing
import UIKit
@testable import AscendApp

/// Sign in with Apple and Google Sign-In present over the window this resolver picks. An
/// unanchored Apple request let the system pick the window itself, which fails when the
/// foreground scene or key window is ambiguous.
@MainActor
struct SignInPresentationWindowTests {
    final class FakeWindow: SignInPresentationWindowCandidate {
        let name: String
        let isKeyWindow: Bool

        init(_ name: String, isKey: Bool = false) {
            self.name = name
            self.isKeyWindow = isKey
        }
    }

    struct FakeScene: SignInPresentationSceneCandidate {
        let activationState: UIScene.ActivationState
        var keyWindow: FakeWindow?
        var windows: [FakeWindow]
    }

    private func names(_ scenes: [FakeScene]) -> [String] {
        SignInPresentationWindow.candidates(in: scenes).map(\.name)
    }

    @Test func theForegroundActiveSceneWinsWhereverItSitsInTheList() {
        let scenes = [
            FakeScene(activationState: .background, keyWindow: nil, windows: [FakeWindow("background")]),
            FakeScene(activationState: .foregroundInactive, keyWindow: nil, windows: [FakeWindow("inactive")]),
            FakeScene(activationState: .foregroundActive, keyWindow: nil, windows: [FakeWindow("active")]),
        ]

        #expect(names(scenes) == ["active", "inactive", "background"])
    }

    @Test func anUnattachedSceneIsNeverChosen() {
        let scenes = [
            FakeScene(activationState: .unattached, keyWindow: nil, windows: [FakeWindow("unattached")]),
            FakeScene(activationState: .background, keyWindow: nil, windows: [FakeWindow("background")]),
        ]

        #expect(names(scenes) == ["background"])
    }

    @Test func theScenesKeyWindowBeatsItsOtherWindows() {
        let key = FakeWindow("key")
        let scene = FakeScene(
            activationState: .foregroundActive,
            keyWindow: key,
            windows: [FakeWindow("first"), FakeWindow("flagged", isKey: true), key]
        )

        #expect(names([scene]) == ["key"])
    }

    @Test func aWindowFlaggedKeyBeatsTheFirstWindowWhenTheSceneReportsNone() {
        let scene = FakeScene(
            activationState: .foregroundActive,
            keyWindow: nil,
            windows: [FakeWindow("first"), FakeWindow("flagged", isKey: true)]
        )

        #expect(names([scene]) == ["flagged"])
    }

    @Test func theFirstWindowStandsInWhenNothingIsKey() {
        let scene = FakeScene(
            activationState: .foregroundActive,
            keyWindow: nil,
            windows: [FakeWindow("first"), FakeWindow("second")]
        )

        #expect(names([scene]) == ["first"])
    }

    @Test func aSceneWithNoWindowsIsSkipped() {
        let scenes = [
            FakeScene(activationState: .foregroundActive, keyWindow: nil, windows: []),
            FakeScene(activationState: .foregroundInactive, keyWindow: nil, windows: [FakeWindow("inactive")]),
        ]

        #expect(names(scenes) == ["inactive"])
    }

    @Test func theAppleAnchorIsTheResolvedForegroundWindow() throws {
        let performer = AppleAuthorizationPerformer()
        let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
        let expected = try #require(SignInPresentationWindow.connectedCandidates().first)

        #expect(performer.presentationAnchor(for: controller) === expected)
    }
}
