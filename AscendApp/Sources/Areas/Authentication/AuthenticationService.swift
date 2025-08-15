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

enum AuthenticationError: LocalizedError {
    case noClientID
    case noRootViewController
    case noIDToken
    case signInFailed(String)
    case signOutFailed(String)
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
        }
    }
}

@MainActor
class AuthenticationService {

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

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            print("User signed out successfully")
        } catch {
            throw AuthenticationError.signOutFailed(error.localizedDescription)
        }
    }
}
