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
    case emailPasswordSignInFailed(String)
    case signOutFailed(String)
    case appleSignInFailed(String)
    case invalidAppleCredential
}

extension AuthenticationError {
    /// User-friendly error description shown to users
    var errorDescription: String? {
        switch self {
        case .noClientID, .noRootViewController, .noIDToken, .invalidAppleCredential:
            return "Something went wrong. Please try again."
        case .signInFailed, .emailPasswordSignInFailed, .appleSignInFailed:
            return "Unable to sign in. Please check your connection and try again."
        case .signOutFailed:
            return "Unable to sign out. Please try again."
        }
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
        case .emailPasswordSignInFailed(let error):
            return "Email/password sign-in failed: \(error)"
        case .signOutFailed(let error):
            return "Sign-out failed: \(error)"
        case .appleSignInFailed(let error):
            return "Apple Sign-in failed: \(error)"
        case .invalidAppleCredential:
            return "Invalid Apple Sign-in credential"
        }
    }
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
class AuthenticationService: NSObject, ASAuthorizationControllerDelegate {

    /// An Apple authorization resolved for reauthentication, before it is
    /// exchanged with Firebase.
    private struct AppleAuthorization {
        let credential: AuthCredential
        let authorizationCode: String?
    }

    private var currentNonce: String?
    private var signInContinuation: CheckedContinuation<User, Error>?
    private var appleReauthContinuation: CheckedContinuation<AppleAuthorization, Error>?

    func signInWithGoogle() async throws -> User {
        // Get Firebase client ID
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthenticationError.noClientID
        }

        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Get root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw AuthenticationError.noRootViewController
        }

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
            if let gidError = error as? GIDSignInError {
                switch gidError.code {
                case .canceled:
                    // User canceled - not an error
                    throw CancellationError()
                default:
                    throw AuthenticationError.signInFailed(error.localizedDescription)
                }
            }
            
            throw AuthenticationError.signInFailed(error.localizedDescription)
        }
    }

    func signInWithEmail(email: String, password: String) async throws -> User {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            debugLog("Firebase email sign-in succeeded")
            return result.user
        } catch {
            throw AuthenticationError.emailPasswordSignInFailed(error.localizedDescription)
        }
    }

    func signInWithApple() async throws -> User {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                // Generate nonce for security
                let nonce = try randomNonceString()
                currentNonce = nonce
                self.signInContinuation = continuation

                let appleIDProvider = ASAuthorizationAppleIDProvider()
                let request = appleIDProvider.createRequest()
                request.requestedScopes = [.email]
                request.nonce = sha256(nonce)

                let authorizationController = ASAuthorizationController(authorizationRequests: [request])
                authorizationController.delegate = self
                authorizationController.performRequests()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            debugLog("User signed out successfully")
        } catch {
            throw AuthenticationError.signOutFailed(error.localizedDescription)
        }
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

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationService {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        // Check if this is a reauthentication flow (credential-only)
        if let appleReauthContinuation = appleReauthContinuation {
            do {
                let appleAuthorization = try handleAppleAuthorizationForReauth(authorization)
                self.appleReauthContinuation = nil
                appleReauthContinuation.resume(returning: appleAuthorization)
            } catch {
                self.appleReauthContinuation = nil
                appleReauthContinuation.resume(throwing: error)
            }
            return
        }

        // Regular sign-in flow
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            signInContinuation?.resume(throwing: AuthenticationError.invalidAppleCredential)
            return
        }

        guard let nonce = currentNonce else {
            signInContinuation?.resume(throwing: AuthenticationError.appleSignInFailed("Invalid state: A login callback was received, but no login request was sent."))
            return
        }

        guard let appleIDToken = appleIDCredential.identityToken else {
            signInContinuation?.resume(throwing: AuthenticationError.appleSignInFailed("Unable to fetch identity token"))
            return
        }

        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            signInContinuation?.resume(throwing: AuthenticationError.appleSignInFailed("Unable to serialize token string from data"))
            return
        }

        let credential = OAuthProvider.credential(providerID: AuthProviderID.apple,
                                                  idToken: idTokenString,
                                                  rawNonce: nonce)

        Task {
            do {
                let result = try await Auth.auth().signIn(with: credential)
                let firebaseUser = result.user
                debugLog("Firebase Apple sign-in succeeded")

                signInContinuation?.resume(returning: firebaseUser)
            } catch {
                signInContinuation?.resume(throwing: AuthenticationError.appleSignInFailed(error.localizedDescription))
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let authError = error as? ASAuthorizationError
        let errorToThrow: Error

        if let authError = authError {
            switch authError.code {
            case .canceled:
                errorToThrow = CancellationError()
            case .unknown:
                errorToThrow = AuthenticationError.appleSignInFailed("Apple Sign-in failed with unknown error")
            case .invalidResponse:
                errorToThrow = AuthenticationError.appleSignInFailed("Apple Sign-in received invalid response")
            case .notHandled:
                errorToThrow = AuthenticationError.appleSignInFailed("Apple Sign-in request not handled")
            case .failed:
                errorToThrow = AuthenticationError.appleSignInFailed("Apple Sign-in failed")
            case .notInteractive:
                errorToThrow = AuthenticationError.appleSignInFailed("Apple Sign-in requires user interaction")
            default:
                errorToThrow = AuthenticationError.appleSignInFailed("Apple Sign-in failed with unknown error")
            }
        } else {
            errorToThrow = AuthenticationError.appleSignInFailed(error.localizedDescription)
        }

        // Resume whichever continuation is active
        if let appleReauthContinuation = appleReauthContinuation {
            self.appleReauthContinuation = nil
            appleReauthContinuation.resume(throwing: errorToThrow)
        } else {
            signInContinuation?.resume(throwing: errorToThrow)
        }
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

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw AuthenticationError.noRootViewController
        }

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
            throw AuthenticationError.signInFailed(error.localizedDescription)
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

        // Get fresh Apple credential
        let appleAuthorization = try await getAppleAuthorization()

        try await user.reauthenticate(with: appleAuthorization.credential)
        debugLog("User reauthenticated with Apple")

        return ReauthenticationResult(
            appleAuthorizationCode: appleAuthorization.authorizationCode
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

    /// Get an Apple authorization without signing in (for reauthentication)
    private func getAppleAuthorization() async throws -> AppleAuthorization {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let nonce = try randomNonceString()
                self.currentNonce = nonce

                let appleIDProvider = ASAuthorizationAppleIDProvider()
                let request = appleIDProvider.createRequest()
                request.requestedScopes = [.email]
                request.nonce = sha256(nonce)

                // Store continuation for credential-only flow
                self.appleReauthContinuation = continuation

                let authorizationController = ASAuthorizationController(authorizationRequests: [request])
                authorizationController.delegate = self
                authorizationController.performRequests()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Helper to handle Apple authorization for reauthentication
    private func handleAppleAuthorizationForReauth(_ authorization: ASAuthorization) throws -> AppleAuthorization {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthenticationError.invalidAppleCredential
        }

        guard let nonce = currentNonce else {
            throw AuthenticationError.appleSignInFailed("Invalid state: no nonce")
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthenticationError.appleSignInFailed("Unable to fetch identity token")
        }

        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idTokenString,
            rawNonce: nonce
        )

        return AppleAuthorization(
            credential: credential,
            authorizationCode: appleIDCredential.authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }
        )
    }
}
