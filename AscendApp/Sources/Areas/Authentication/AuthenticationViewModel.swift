//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
@preconcurrency import FirebaseAuth
import Observation
@preconcurrency import GoogleSignIn
import FirebaseCore

enum AuthenticationState {
    case authenticated
    case authenticating
    case unauthenticated
}

@MainActor
@Observable
class AuthenticationViewModel {
    var displayName: String = ""
    var user: User?
    var authenticationState: AuthenticationState = .unauthenticated
    var errorMessage: String = ""

    init() {
        registerAuthStateHandler()
    }
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    func registerAuthStateHandler() {
        if authStateHandle == nil {
            authStateHandle = Auth.auth().addStateDidChangeListener({ auth, user in
                self.user = user
                self.authenticationState = user == nil ? .unauthenticated : .authenticated
                self.displayName = user?.displayName ?? "Unknown"
            })
        }
    }
}

extension AuthenticationViewModel {
  func signInWithGoogle() async -> Bool {
    guard let clientID = FirebaseApp.app()?.options.clientID else {
      fatalError("No client ID found in Firebase configuration")
    }
    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

      guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first,
            let rootViewController = window.rootViewController else {
      print("There is no root view controller!")
      return false
    }

      do {
        let userAuthentication = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        let user = userAuthentication.user
          guard let idToken = user.idToken else {
              print("ID token is missing")
              return false
          }
        let accessToken = user.accessToken

        let credential = GoogleAuthProvider.credential(withIDToken: idToken.tokenString,
                                                       accessToken: accessToken.tokenString)

        let result = try await Auth.auth().signIn(with: credential)
        let firebaseUser = result.user
        print("User \(firebaseUser.uid) signed in with email \(firebaseUser.email ?? "unknown")")
        return true
      }
      catch {
        print(error.localizedDescription)
        self.errorMessage = error.localizedDescription
        return false
      }
  }

    func signOut() -> Bool {
        do {
            try Auth.auth().signOut()
            errorMessage = ""
            return true
        }
        catch {
            errorMessage = error.localizedDescription
            print(error.localizedDescription)
            return false
        }
    }
}
