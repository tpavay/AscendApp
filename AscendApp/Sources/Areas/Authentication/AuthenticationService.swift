////
////  AuthenticationService.swift
////  AscendApp
////
////  Created by Tyler Pavay on 8/13/25.
////
//
//import FirebaseAuth
//import FirebaseCore
//import GoogleSignIn
//
//enum AuthenticationError: LocalizedError {
//    case signOutError(errorText: String)
//}
//
//extension AuthenticationError {
//    var localizedDescription: String {
//        switch self {
//        case .signOutError(let errorText): return "Error occurred while signing out. \(errorText)"
//        }
//    }
//}
//
//class AuthenticationService {
//
//    func signInWithGoogle() async -> Bool {
//          guard let clientID = FirebaseApp.app()?.options.clientID else {
//            fatalError("No client ID found in Firebase configuration")
//          }
//          let config = GIDConfiguration(clientID: clientID)
//          GIDSignIn.sharedInstance.configuration = config
//
//          let rootViewController = await MainActor.run {
//              guard let windowScene = UIApplication.shared.connectedScenes.first as?
//      UIWindowScene,
//                    let window = windowScene.windows.first,
//                    let rootViewController = window.rootViewController else {
//                  return nil as UIViewController?
//              }
//              return rootViewController
//          }
//
//          guard let rootViewController else {
//              print("There is no root view controller!")
//              return false
//          }
//
//        do {
//          let userAuthentication = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
//
//          let user = userAuthentication.user
//            guard let idToken = user.idToken else {
//                print("ID token is missing")
//                return false
//            }
//          let accessToken = user.accessToken
//
//          let credential = GoogleAuthProvider.credential(withIDToken: idToken.tokenString,
//                                                         accessToken: accessToken.tokenString)
//
//          let result = try await Auth.auth().signIn(with: credential)
//          let firebaseUser = result.user
//          print("User \(firebaseUser.uid) signed in with email \(firebaseUser.email ?? "unknown")")
//          return true
//        }
//        catch {
//          print(error.localizedDescription)
//          return false
//        }
//      }
//
////    @MainActor
////    func signInWithGoogle() async -> Bool {
////      guard let clientID = FirebaseApp.app()?.options.clientID else {
////        fatalError("No client ID found in Firebase configuration")
////      }
////      let config = GIDConfiguration(clientID: clientID)
////      GIDSignIn.sharedInstance.configuration = config
////
////        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
////              let window = windowScene.windows.first,
////              let rootViewController = window.rootViewController else {
////        print("There is no root view controller!")
////        return false
////      }
////
////        do {
////          let userAuthentication = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
////
////          let user = userAuthentication.user
////            guard let idToken = user.idToken else {
////                print("ID token is missing")
////                return false
////            }
////          let accessToken = user.accessToken
////
////          let credential = GoogleAuthProvider.credential(withIDToken: idToken.tokenString,
////                                                         accessToken: accessToken.tokenString)
////
////          let result = try await Auth.auth().signIn(with: credential)
////          let firebaseUser = result.user
////          print("User \(firebaseUser.uid) signed in with email \(firebaseUser.email ?? "unknown")")
////          return true
////        }
////        catch {
////          print(error.localizedDescription)
////          return false
////        }
////    }
//    
//    func signOut() throws(AuthenticationError) {
//        do {
//            try Auth.auth().signOut()
//        }
//        catch {
//            throw .signOutError(errorText: error.localizedDescription)
//        }
//    }
//}


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
}

extension AuthenticationError {
    var errorDescription: String? {
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
        }
    }
}

@MainActor
class AuthenticationService: NSObject, ASAuthorizationControllerDelegate {
    
    private var currentNonce: String?
    private var signInContinuation: CheckedContinuation<User, Error>?

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
            let firebaseUser = result.user

            print("User \(firebaseUser.uid) signed in with email \(firebaseUser.email ?? "unknown")")
            return firebaseUser

        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.signInFailed(error.localizedDescription)
        }
    }

    func signInWithApple() async throws -> User {
        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            
            // Generate nonce for security
            let nonce = randomNonceString()
            currentNonce = nonce
            
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            
            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.performRequests()
        }
    }
    
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            print("User signed out successfully")
        } catch {
            throw AuthenticationError.signOutFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Apple Sign In Helper Methods
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
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
                print("User \(firebaseUser.uid) signed in with Apple ID \(appleIDCredential.user)")
                signInContinuation?.resume(returning: firebaseUser)
            } catch {
                signInContinuation?.resume(throwing: AuthenticationError.appleSignInFailed(error.localizedDescription))
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        signInContinuation?.resume(throwing: AuthenticationError.appleSignInFailed(error.localizedDescription))
    }
}
