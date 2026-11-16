//
//  AuthenticationService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/13/25.
//

@preconcurrency import FirebaseAuth
import FirebaseCore
@preconcurrency import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit

enum AuthenticationError: LocalizedError {
    case noClientID
    case noRootViewController
    case noIDToken
    case signInFailed(String)
    case signOutFailed(String)
    case appleSignInFailed(String)
    case invalidAppleCredential
    /// A provider, Firebase or the network refused a sign-in, with the error that says which.
    /// Kept apart from the string cases above so the message and the Sentry tags are decided by
    /// what the error was, not by the fact that a sign-in failed.
    case providerFailure(AuthenticationFailureDiagnostics)
}

extension AuthenticationError {
    /// User-friendly error description shown to users.
    ///
    /// Only a connectivity failure may mention the connection. The one sentence this used to be
    /// for every sign-in failure told App Review, on a phone with a working connection, that the
    /// app could not tell it was online (Guideline 2.1(a), 1.3.0 build 2026111401).
    var errorDescription: String? {
        switch self {
        case .noClientID, .noRootViewController, .noIDToken, .invalidAppleCredential:
            return "Something went wrong. Please try again."
        case .signInFailed, .appleSignInFailed:
            return "We couldn't sign you in. Try again in a moment."
        case .signOutFailed:
            return "Unable to sign out. Please try again."
        case .providerFailure(let diagnostics):
            switch diagnostics.kind {
            case .connectivity:
                return "Can't reach Ascend right now. Check your connection and try again."
            case .appleAuthorization:
                return "Sign in with Apple didn't finish on this device."
            case .providerRejected:
                return "We couldn't sign you in. Try again in a moment."
            }
        }
    }

    /// What the sign-in screen shows. Apple's own authorization failing is the one failure with
    /// causes a climber can fix on the phone - no Apple Account signed in, two-factor authentication
    /// off - and a way on that the screen has: the other provider, one button away.
    var signInScreenDescription: String? {
        if case .providerFailure(let diagnostics) = self, diagnostics.kind == .appleAuthorization {
            return Self.appleFailureGuidance
        }
        return errorDescription
    }

    static let appleFailureGuidance =
        "Sign in with Apple didn't finish. Make sure this phone is signed in to your Apple Account in Settings and that two-factor authentication is on, then try again - or continue with Google."

    /// The same facts, typed for the `onboarding_auth_failed` event.
    var analyticsParameters: [String: TelemetryValue] {
        if case .providerFailure(let diagnostics) = self {
            return diagnostics.analyticsParameters
        }
        return [:]
    }

    /// The tags recorded beside a failed sign-in: the kind, and the domains and codes behind it.
    var telemetryInfo: [String: String] {
        if case .providerFailure(let diagnostics) = self {
            return diagnostics.telemetryInfo
        }
        return [:]
    }

    /// Technical details for logging/debugging (not shown to users)
    var technicalDescription: String {
        switch self {
        case .noClientID:
            return "No client ID found in Firebase configuration"
        case .noRootViewController:
            return "Unable to find root view controller"
        case .noIDToken:
            return "ID token is missing from Google Sign-In"
        case .signInFailed(let error):
            return "Sign-in failed: \(error)"
        case .signOutFailed(let error):
            return "Sign-out failed: \(error)"
        case .appleSignInFailed(let error):
            return "Apple Sign-in failed: \(error)"
        case .invalidAppleCredential:
            return "Invalid Apple Sign-in credential"
        case .providerFailure(let diagnostics):
            return "Sign-in failed (\(diagnostics.kind.rawValue), \(diagnostics.errorDomain) \(diagnostics.errorCode)): \(diagnostics.detail)"
        }
    }
}

/// The climber closed Apple's sheet. Not a failure and never shown as one, but it carries the attempt's
/// trace: a cancel that arrives one or two seconds after the tap is not a person reading a sheet.
struct AppleAuthorizationCancelled: Error {
    let trace: AppleAuthorizationTrace?
}

/// Outcome of a successful reauthentication, carrying anything the caller needs
/// for follow-up work that must happen while the user is still signed in.
struct ReauthenticationResult: Sendable {
    /// Apple's single-use authorization code, present only for Sign in with Apple.
    /// Apple requires this to revoke the user's token on account deletion
    /// (App Store guideline 5.1.1(v)).
    var appleAuthorizationCode: String?
}

@MainActor
class AuthenticationService {

    /// An Apple authorization resolved for reauthentication, before it is
    /// exchanged with Firebase.
    private struct AppleAuthorization {
        let credential: AuthCredential
        let authorizationCode: String?
    }

    /// Both the name and the email are requested, because Authentication Services
    /// is the only place either one is ever offered: Apple populates them on the
    /// first authorization for an Apple ID and app pair and never again. Asking
    /// the climber afterwards for something this request could have supplied is
    /// what App Review refuses under Guideline 4.
    static let appleRequestedScopes: [ASAuthorization.Scope] = [.fullName, .email]

    private let appleAuthorization: any AppleAuthorizationPerforming
    private let signInIdentityStore: SignInIdentityStore

    init(
        signInIdentityStore: SignInIdentityStore = .shared,
        appleAuthorization: any AppleAuthorizationPerforming = AppleAuthorizationPerformer()
    ) {
        self.signInIdentityStore = signInIdentityStore
        self.appleAuthorization = appleAuthorization
    }

    func signInWithGoogle() async throws -> User {
        // Get Firebase client ID
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthenticationError.noClientID
        }

        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        let rootViewController = try presentingViewController()

        do {
            // Perform Google Sign-In
            let userAuthentication = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            let user = userAuthentication.user
            guard let idToken = user.idToken else {
                throw AuthenticationError.noIDToken
            }
            let accessToken = user.accessToken

            // Create Firebase credential
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken.tokenString,
                accessToken: accessToken.tokenString
            )

            // Sign in to Firebase
            let result = try await Auth.auth().signIn(with: credential)
            debugLog("Firebase Google sign-in succeeded")
            return result.user

        } catch let error as AuthenticationError {
            throw error
        } catch {
            // Check for Google Sign-in cancellation
            if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                // User canceled - not an error
                throw CancellationError()
            }

            throw Self.providerFailure(for: error)
        }
    }

    func signInWithEmail(email: String, password: String) async throws -> User {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            debugLog("Firebase email sign-in succeeded")
            return result.user
        } catch {
            throw Self.providerFailure(for: error)
        }
    }

    func signInWithApple() async throws -> User {
        let authorization = try await requestAppleAuthorization()

        // `fullName` is handed to Firebase as well, not just to Ascend's own
        // capture: this is the overload that lets Firebase Auth set the account's
        // `displayName` from the credential, and Apple populates `fullName` on
        // the first authorization only. Passing nil later is harmless - Firebase
        // does not clear a display name it already has.
        let credential = OAuthProvider.appleCredential(
            withIDToken: authorization.idToken,
            rawNonce: authorization.rawNonce,
            fullName: authorization.credential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            debugLog("Firebase Apple sign-in succeeded")
            return result.user
        } catch {
            throw Self.providerFailure(for: error)
        }
    }

    /// One Apple authorization: a fresh nonce, the request, the sheet, and the identity token it
    /// returned. Sign-in and reauthentication both come through here, so there is one place that
    /// raises the sheet and one place that records what it supplied.
    private func requestAppleAuthorization() async throws -> (credential: AppleAuthorizationCredential, idToken: String, rawNonce: String) {
        let nonce = try randomNonceString()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = Self.appleRequestedScopes
        request.nonce = sha256(nonce)

        let outcome = await appleAuthorization.perform(request)

        let credential: AppleAuthorizationCredential
        switch outcome.result {
        case .failure(let error):
            throw Self.appleAuthorizationFailure(for: error, trace: outcome.trace)
        case .success(let supplied):
            credential = supplied
        }

        // Capture before anything else can fail. Apple supplies the name and
        // email on the first authorization only, so a throw, a cancelled task or
        // a dropped connection between here and the profile write would lose
        // them permanently. Recording every authorization - sign-in and
        // reauthentication alike - means no path exists that sees them and
        // drops them.
        signInIdentityStore.record(credential.suppliedIdentity)

        guard let identityToken = credential.identityToken else {
            throw AuthenticationError.appleSignInFailed("Unable to fetch identity token")
        }
        guard let idToken = String(data: identityToken, encoding: .utf8) else {
            throw AuthenticationError.appleSignInFailed("Unable to serialize token string from data")
        }

        return (credential, idToken, nonce)
    }

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            debugLog("User signed out successfully")
        } catch {
            throw AuthenticationError.signOutFailed(error.localizedDescription)
        }
    }
    
    /// The view controller Google Sign-In presents from.
    private func presentingViewController() throws -> UIViewController {
        for window in SignInPresentationWindow.connectedCandidates() {
            if let rootViewController = window.rootViewController {
                // Presenting onto a controller that already has something modal
                // over it silently does nothing, so hand Google the topmost one.
                return rootViewController.topmostPresentedViewController
            }
        }

        throw AuthenticationError.noRootViewController
    }

    // MARK: - Apple Sign In Helper Methods
    private func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = try (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    throw AuthenticationError.appleSignInFailed("Unable to prepare Apple Sign-in.")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// MARK: - Failure mapping
extension AuthenticationService {
    /// What Apple's authorization controller failing becomes. A dismissed sheet is the climber's
    /// choice and ends quietly; every other code is the system sheet failing before any Ascend
    /// request was made, so it is recorded with Apple's own domain and code and never described
    /// as a connection problem unless the error itself says the network was the cause.
    nonisolated static func appleAuthorizationFailure(for error: Error, trace: AppleAuthorizationTrace? = nil) -> Error {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            return AppleAuthorizationCancelled(trace: trace)
        }
        if let apple = error as? AppleAuthorizationError, apple == .alreadyInProgress {
            return AuthenticationError.signInFailed("Sign in with Apple is already in progress")
        }
        if let authenticationError = error as? AuthenticationError {
            return authenticationError
        }
        return AuthenticationError.providerFailure(
            AuthenticationFailureDiagnostics(error: error, otherwise: .appleAuthorization, appleTrace: trace)
        )
    }

    /// What a failed Firebase, Google or network call becomes.
    nonisolated static func providerFailure(for error: Error) -> AuthenticationError {
        .providerFailure(AuthenticationFailureDiagnostics(error: error, otherwise: .providerRejected))
    }

    func updateUserDisplayName(displayName: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.signInFailed("No authenticated user found")
        }

        try await Self.commitValidatedDisplayName(displayName) {
            validatedDisplayName in
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = validatedDisplayName

            try await changeRequest.commitChanges()
        }
    }

    @discardableResult
    static func commitValidatedDisplayName(
        _ displayName: String,
        mutation: (String) async throws -> Void
    ) async throws -> String {
        let validatedDisplayName = try DisplayNamePolicy.validated(displayName)
        try await mutation(validatedDisplayName)
        return validatedDisplayName
    }

    // MARK: - Reauthentication

    /// Reauthenticate the current user with Google
    func reauthenticateWithGoogle() async throws -> ReauthenticationResult {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.signInFailed("No authenticated user found")
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthenticationError.noClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        let rootViewController = try presentingViewController()

        do {
            let userAuthentication = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            let googleUser = userAuthentication.user
            guard let idToken = googleUser.idToken else {
                throw AuthenticationError.noIDToken
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken.tokenString,
                accessToken: googleUser.accessToken.tokenString
            )

            try await user.reauthenticate(with: credential)
            debugLog("User reauthenticated with Google")
            return ReauthenticationResult(appleAuthorizationCode: nil)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw CancellationError()
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw Self.providerFailure(for: error)
        }
    }

    /// Reauthenticate the current user with Apple
    ///
    /// Returns the fresh authorization code alongside the reauthentication so
    /// callers can revoke the user's Sign in with Apple token before deleting
    /// their account. The code is single-use and short-lived, so it is only
    /// useful to the caller that requested this reauthentication.
    func reauthenticateWithApple() async throws -> ReauthenticationResult {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.signInFailed("No authenticated user found")
        }

        // Get fresh Apple credential. A closed sheet stays a plain cancellation here: account deletion
        // already treats that as the climber backing out.
        let authorization: (credential: AppleAuthorizationCredential, idToken: String, rawNonce: String)
        do {
            authorization = try await requestAppleAuthorization()
        } catch is AppleAuthorizationCancelled {
            throw CancellationError()
        }
        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: authorization.idToken,
            rawNonce: authorization.rawNonce
        )

        try await user.reauthenticate(with: credential)
        debugLog("User reauthenticated with Apple")

        return ReauthenticationResult(
            appleAuthorizationCode: authorization.credential.authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    /// Revokes the user's Sign in with Apple token.
    ///
    /// Apple has required this on account deletion since 2022 (App Store
    /// guideline 5.1.1(v)). Without it the app keeps appearing under
    /// Settings > Apple ID > Sign in with Apple after the account is gone.
    /// The authorization code must be fresh: Apple rejects reused codes.
    func revokeAppleToken(authorizationCode: String) async throws {
        try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
        debugLog("Revoked Sign in with Apple token")
    }

}

private extension UIViewController {
    /// The controller actually on screen, walking past anything already presented
    /// modally over this one.
    ///
    /// A controller caught mid-transition is not a controller anything can be
    /// presented from: UIKit drops the presentation and Google's sheet never
    /// appears. So the walk stops before one that is being dismissed - it is on
    /// its way out - and before one that is being presented - it is not settled
    /// in the hierarchy yet.
    var topmostPresentedViewController: UIViewController {
        var topmost = self
        while let presented = topmost.presentedViewController,
              !presented.isBeingDismissed,
              !presented.isBeingPresented {
            topmost = presented
        }
        return topmost
    }
}
