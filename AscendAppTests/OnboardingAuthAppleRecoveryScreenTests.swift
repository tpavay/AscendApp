import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The sign-in screen as a climber meets it after Apple's sheet fails.
///
/// 1.3.0 unmounted this screen the instant Apple was tapped and drew a spinner in its place; a
/// refusal then returned to a freshly built copy of the screen with a sentence that blamed the
/// connection and nothing to press that said "try again". Here the screen is hosted, driven through
/// the real view model with a scripted Apple, and read back from the accessibility tree.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingAuthAppleRecoveryScreenTests {
    private static let phone = CGSize(width: 393, height: 852)
    private static let apple = "Continue with Apple"
    private static let appleAgain = "Try Apple again"
    private static let google = "Continue with Google"

    private func signedOutScreen(model: AuthenticationViewModel) -> some View {
        let suite = "apple-recovery-screen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer
        )
        coordinator.go(to: .auth)

        return OnboardingAuthScreen(coordinator: coordinator)
            .environment(model)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }

    private func model(failing times: Int) async -> (AuthenticationViewModel, ScriptedApplePerformer) {
        let performer = ScriptedApplePerformer((0..<times).map { _ in ScriptedApplePerformer.failure(code: .unknown) })
        let defaults = UserDefaults(suiteName: "apple-recovery-screen-store-\(UUID().uuidString)")!
        let model = AuthenticationViewModel(
            observesFirebaseAuth: false,
            authenticationService: AuthenticationService(
                signInIdentityStore: SignInIdentityStore(userDefaults: defaults),
                appleAuthorization: performer
            )
        )
        for _ in 0..<times { await model.signInWithApple() }
        return (model, performer)
    }

    /// Where each of `labels` sits, in window points, once all of them are there.
    private static func frames(on screen: HostedScreen, of labels: [String]) async throws -> [String: CGRect] {
        func read(_ elements: [NSObject]) -> [String: CGRect] {
            Dictionary(elements.compactMap { element in
                guard let label = element.accessibilityLabel, labels.contains(label) else { return nil }
                return (label, screen.window.convert(element.accessibilityFrame, from: nil))
            }, uniquingKeysWith: { first, _ in first })
        }
        let elements = try await screen.elements(reading: 400) { read($0).count == labels.count }
        return read(elements)
    }

    @Test("After one refusal: the guidance, a retry on the Apple button, Google below it")
    func theFirstRefusalOffersATryAgainAndGoogleOneButtonDown() async throws {
        let (model, _) = await model(failing: 1)

        try await RenderedScreen.host(UIHostingController(rootView: signedOutScreen(model: model)), size: Self.phone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy { $0.contains("try apple again") }

            #expect(copy.contains("sign in with apple didn't finish"), "\(copy)")
            #expect(copy.contains("signed in to your apple account in settings"), "\(copy)")
            #expect(copy.contains("two-factor authentication is on"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(!copy.contains("check your connection"), "\(copy)")
            #expect(!copy.contains("continue with apple"), "the Apple button now reads as a retry: \(copy)")

            let frames = try await Self.frames(on: hosted, of: [Self.appleAgain, Self.google])
            let apple = try #require(frames[Self.appleAgain])
            let google = try #require(frames[Self.google])
            #expect(apple.minY < google.minY, "Apple is still first after one refusal: \(apple) \(google)")
        }
    }

    @Test("After two refusals in a row Google takes the first place and Apple stays one tap away")
    func theSecondRefusalPutsGoogleFirst() async throws {
        let (model, _) = await model(failing: 2)

        try await RenderedScreen.host(UIHostingController(rootView: signedOutScreen(model: model)), size: Self.phone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy { $0.contains("try apple again") }
            #expect(copy.contains("continue with google"), "\(copy)")

            let frames = try await Self.frames(on: hosted, of: [Self.appleAgain, Self.google])
            let apple = try #require(frames[Self.appleAgain])
            let google = try #require(frames[Self.google])
            #expect(google.minY < apple.minY, "Google leads after two refusals: \(google) \(apple)")
            #expect(model.authenticationState == .unauthenticated, "both buttons are live")
        }
    }

    @Test("While Apple is working the screen stays, with both buttons and a signing-in line")
    func theScreenStaysMountedWhileAppleWorks() async throws {
        let defaults = UserDefaults(suiteName: "apple-recovery-screen-store-\(UUID().uuidString)")!
        let model = AuthenticationViewModel(
            observesFirebaseAuth: false,
            authenticationService: AuthenticationService(
                signInIdentityStore: SignInIdentityStore(userDefaults: defaults),
                appleAuthorization: ScriptedApplePerformer()
            )
        )
        model.authenticationState = .authenticatingWithApple

        // The root keeps this screen for every authenticating state, so a refusal lands on it.
        #expect(
            AppRootRouteResolver.resolve(
                updatePresentation: nil,
                authenticationState: model.authenticationState,
                userId: nil,
                entitlementState: .unknown,
                requiredEntitlementID: "app_access"
            ) == .preAuthOnboarding
        )

        try await RenderedScreen.host(UIHostingController(rootView: signedOutScreen(model: model)), size: Self.phone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy { $0.contains("signing in...") }

            #expect(copy.contains("continue with apple"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(!copy.contains("sign in error"), "\(copy)")
        }
    }
}
