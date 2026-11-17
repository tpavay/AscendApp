import AuthenticationServices
import FirebaseAuth
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// App Review rejected 1.3.0 (build 2026111401) under Guideline 2.1(a) on 2026-11-16: an
/// iPhone 17 Pro Max with a working connection tapped Continue with Apple, Apple's own
/// authorization failed (Sentry `ASCEND-IOS-1F`, "Apple Sign-in failed with unknown error"), and
/// the screen read "Unable to sign in. Please check your connection and try again." - which the
/// reviewer took for the app not recognising the internet. Every failure shared that sentence.
/// These tests hold the sentence to what actually failed.
@MainActor
struct AuthenticationFailureMessagingTests {
    private static let connectionWording = "connection"

    private func message(of error: Error) throws -> String {
        let authError = try #require(error as? AuthenticationError, "\(error)")
        return try #require(authError.signInScreenDescription)
    }

    // MARK: - The reviewer's failure

    @Test(arguments: [
        ASAuthorizationError.Code.unknown,
        .invalidResponse,
        .notHandled,
        .failed,
        .notInteractive
    ])
    func appleRefusingToAuthorizeIsNeverDescribedAsAConnectionProblem(code: ASAuthorizationError.Code) throws {
        let appleError = NSError(domain: ASAuthorizationError.errorDomain, code: code.rawValue)

        let thrown = AuthenticationService.appleAuthorizationFailure(for: appleError)
        let text = try message(of: thrown)

        #expect(!text.localizedCaseInsensitiveContains(Self.connectionWording), "\(text)")
        #expect(text.contains("Sign in with Apple didn't finish"), "\(text)")
        #expect(text.contains("Apple Account"), "the fixable cause is named: \(text)")
        #expect(text.contains("two-factor"), "the other fixable cause is named: \(text)")
        #expect(text.contains("continue with Google"), "the way on is the other provider: \(text)")
    }

    @Test
    func theReviewersFailureIsRecordedWithAppleOwnDomainAndCode() throws {
        let appleError = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.unknown.rawValue)

        let thrown = try #require(AuthenticationService.appleAuthorizationFailure(for: appleError) as? AuthenticationError)

        #expect(thrown.telemetryInfo == [
            "failure_kind": "appleAuthorization",
            "error_domain": ASAuthorizationError.errorDomain,
            "error_code": "1000",
            "apple_error_name": "unknown"
        ])
    }

    @Test
    func theFailureTagsCarryTheProviderToo() {
        let appleError = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.unknown.rawValue)
        let thrown = AuthenticationService.appleAuthorizationFailure(for: appleError)

        let info = AuthenticationViewModel.failureInfo(for: thrown, provider: "apple")

        #expect(info["provider"] == "apple")
        #expect(info["failure_kind"] == "appleAuthorization")
        #expect(info["error_code"] == "1000")
    }

    @Test
    func aDismissedAppleSheetEndsQuietly() {
        let dismissed = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.canceled.rawValue)

        #expect(AuthenticationService.appleAuthorizationFailure(for: dismissed) is AppleAuthorizationCancelled)
    }

    // MARK: - Only a connectivity error says connection

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .timedOut,
        .networkConnectionLost,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .dataNotAllowed,
        .internationalRoamingOff
    ])
    func aTransportErrorOnTheProviderPathIsAConnectionProblem(code: URLError.Code) throws {
        let thrown = AuthenticationService.providerFailure(for: URLError(code))

        let text = try message(of: thrown)

        #expect(text == "Can't reach Ascend right now. Check your connection and try again.")
        #expect(thrown.telemetryInfo["failure_kind"] == "connectivity")
    }

    @Test
    func firebaseReportingItsOwnNetworkErrorIsAConnectionProblem() throws {
        let firebase = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.networkError.rawValue,
            userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet) as NSError]
        )

        let text = try message(of: AuthenticationService.providerFailure(for: firebase))

        #expect(text.contains("Check your connection"), "\(text)")
    }

    @Test
    func aTransportErrorBuriedInsideAnotherErrorIsStillFound() throws {
        let inner = URLError(.timedOut) as NSError
        let middle = NSError(domain: "FIRAuthInternalErrorDomain", code: 9, userInfo: [NSUnderlyingErrorKey: inner])
        let outer = NSError(domain: "com.google.GIDSignIn", code: -1, userInfo: [NSUnderlyingErrorKey: middle])

        let text = try message(of: AuthenticationService.providerFailure(for: outer))

        #expect(text.contains("Check your connection"), "\(text)")
    }

    @Test
    func appleControllerFailingOnATransportErrorIsAConnectionProblem() throws {
        let appleError = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.unknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet) as NSError]
        )

        let text = try message(of: AuthenticationService.appleAuthorizationFailure(for: appleError))

        #expect(text.contains("Check your connection"), "\(text)")
    }

    // MARK: - A reachable server that said no is not a connection problem

    @Test(arguments: [
        AuthErrorCode.invalidCredential,
        .userDisabled,
        .accountExistsWithDifferentCredential,
        .internalError,
        .tooManyRequests
    ])
    func firebaseAnsweringAndRefusingIsNeverDescribedAsAConnectionProblem(code: AuthErrorCode) throws {
        let refusal = NSError(domain: AuthErrorDomain, code: code.rawValue)

        let thrown = AuthenticationService.providerFailure(for: refusal)
        let text = try message(of: thrown)

        #expect(!text.localizedCaseInsensitiveContains(Self.connectionWording), "\(text)")
        #expect(thrown.telemetryInfo["failure_kind"] == "providerRejected")
        #expect(thrown.telemetryInfo["error_code"] == String(code.rawValue))
    }

    @Test
    func aBadServerResponseIsNotAConnectionProblem() throws {
        let text = try message(of: AuthenticationService.providerFailure(for: URLError(.badServerResponse)))

        #expect(!text.localizedCaseInsensitiveContains(Self.connectionWording), "\(text)")
    }

    @Test
    func noSignInFailureOutsideConnectivityEverMentionsTheConnection() {
        let stringCases: [AuthenticationError] = [
            .noClientID,
            .noRootViewController,
            .noIDToken,
            .invalidAppleCredential,
            .signInFailed("x"),
            .appleSignInFailed("x"),
            .signOutFailed("x")
        ]

        for error in stringCases {
            #expect(!(error.errorDescription ?? "").localizedCaseInsensitiveContains(Self.connectionWording), "\(error)")
        }
    }

    // MARK: - On the screen

    @Test(.hostsAWindow)
    func theSignInScreenShowsWhatFailedNotAConnectionSentenceForAnAppleFailure() async throws {
        let suite = "auth-failure-messaging-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: .notificationPrimer)
        coordinator.go(to: .auth)

        let appleError = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.unknown.rawValue)
        let viewModel = AuthenticationViewModel()
        viewModel.errorMessage = AuthenticationViewModel.screenMessage(
            for: AuthenticationService.appleAuthorizationFailure(for: appleError)
        )

        let screen = OnboardingAuthScreen(coordinator: coordinator)
            .environment(viewModel)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let controller = UIHostingController(rootView: screen)

        try await RenderedScreen.host(controller, size: CGSize(width: 393, height: 852), settle: .turns(40)) { hosted in
            let copy = try await hosted.copy { $0.contains("continue with apple") }

            #expect(copy.contains("sign in with apple didn't finish"), "\(copy)")
            #expect(copy.contains("two-factor authentication is on"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(!copy.contains("check your connection"), "\(copy)")
            #expect(!copy.contains("unable to sign in"), "\(copy)")
        }
    }
}
