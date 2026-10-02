import AuthenticationServices
import UIKit

/// Presents Strava's mobile consent page in an `ASWebAuthenticationSession`.
///
/// Strava's redirect comes back one of two ways. Approved in the sheet itself, the session
/// catches it on the callback scheme. Approved in the Strava app - which takes over when it is
/// installed - Strava opens the redirect like any other link, so it reaches the app through
/// `onOpenURL` and is handed to the sheet still waiting for it (`receive(_:)`). A climber
/// already signed in to Strava in Safari is not asked to sign in again.
@MainActor
final class WebStravaAuthorizationPresenter: NSObject, StravaAuthorizationPresenting {
    /// The presenter whose sign-in is waiting for Strava's redirect, if any.
    private static weak var waiting: WebStravaAuthorizationPresenter?

    private var session: ASWebAuthenticationSession?
    private var pending: (callbackScheme: String, continuation: CheckedContinuation<URL?, any Error>)?

    func authorize(_ request: StravaAuthorizationRequest) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            pending = (request.callbackScheme, continuation)
            let session = ASWebAuthenticationSession(
                url: request.authorizeURL,
                callback: .customScheme(request.callbackScheme)
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        self?.finish(.success(nil))
                    } else if let error {
                        self?.finish(.failure(error))
                    } else {
                        self?.finish(.success(callbackURL))
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            Self.waiting = self
            if !session.start() {
                finish(.failure(StravaIntegrationError.other("The Strava sign-in sheet could not open.")))
            }
        }
    }

    /// Hands a redirect that arrived through `onOpenURL` to the sign-in waiting for it.
    ///
    /// Returns false when no sign-in is waiting on that scheme, so the link falls through to
    /// the app's other routes.
    static func receive(_ url: URL) -> Bool {
        guard let waiting,
              let callbackScheme = waiting.pending?.callbackScheme,
              url.scheme?.lowercased() == callbackScheme.lowercased() else {
            return false
        }
        waiting.finish(.success(url))
        return true
    }

    /// Resumes the caller exactly once, whichever of the sheet and `onOpenURL` answers first,
    /// and takes the sheet down if it is still up.
    private func finish(_ result: Result<URL?, any Error>) {
        guard let pending else { return }
        self.pending = nil
        if Self.waiting === self {
            Self.waiting = nil
        }
        let session = self.session
        self.session = nil
        session?.cancel()
        pending.continuation.resume(with: result)
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
