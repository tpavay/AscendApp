import AuthenticationServices
import UIKit

/// Presents Strava's mobile consent page in an `ASWebAuthenticationSession`.
///
/// The session catches the redirect on the app's custom scheme directly, so
/// the code never passes through `onOpenURL`, and a climber already signed in
/// to Strava in Safari is not asked to sign in again.
@MainActor
final class WebStravaAuthorizationPresenter: NSObject, StravaAuthorizationPresenting {
    private var session: ASWebAuthenticationSession?

    func authorize(_ request: StravaAuthorizationRequest) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: request.authorizeURL,
                callback: .customScheme(request.callbackScheme)
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(returning: nil)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: callbackURL)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: StravaIntegrationError.other("The Strava sign-in sheet could not open."))
            }
        }
    }
}

extension WebStravaAuthorizationPresenter: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let foreground = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            if let window = foreground?.keyWindow ?? foreground?.windows.first {
                return window
            }
            guard let foreground else {
                preconditionFailure("A Strava sign-in was started with no window scene to present it in")
            }
            return UIWindow(windowScene: foreground)
        }
    }
}
