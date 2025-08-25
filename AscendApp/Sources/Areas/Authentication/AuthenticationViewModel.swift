//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
import FirebaseAuth
import Observation

enum AuthenticationState {
      case authenticated
      case authenticatingWithApple
      case authenticatingWithGoogle
      case unauthenticated

    /// Specific case for when a user signs in with apple. Apple is very big on privacy so we
    /// are unable to retrieve the user's name when they authenticate with apple. So, once
    /// they are authenticated we can use this state if we don't have their name yet.
    case needsName
  }

@MainActor
@Observable
class AuthenticationViewModel {
    var displayName: String = ""
    var user: User?
    var authenticationState: AuthenticationState = .unauthenticated
    var errorMessage: String?
    var isErrorAlertPresented: Bool = false
    var photoURL: URL?

    private var authenticationService = AuthenticationService()

    init() {
        registerAuthStateHandler()
    }
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    func registerAuthStateHandler() {
        if authStateHandle == nil {
            authStateHandle = Auth.auth().addStateDidChangeListener({ auth, user in
                self.user = user
                self.authenticationState = self.getAuthenticationState()
                self.displayName = user?.displayName ?? UserDefaults.standard.string(forKey: "displayName") ?? ""
                self.photoURL = user?.photoURL ?? URL(string: "")
            })
        }
    }
}

@MainActor
extension AuthenticationViewModel {
    func signOut() {
        do {
            try authenticationService.signOut()
            errorMessage = nil
        }
        catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        authenticationState = .authenticatingWithGoogle
        errorMessage = nil
        
        do {
            _ = try await authenticationService.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
            authenticationState = .unauthenticated
        }
    }
    
    func signInWithApple() async {
        authenticationState = .authenticatingWithApple
        errorMessage = nil

        do {
            _ = try await authenticationService.signInWithApple()
        } catch {
            errorMessage = error.localizedDescription
            authenticationState = .unauthenticated
        }
    }

    func setDisplayName(firstName: String, lastName: String) async {
        do {
            try await authenticationService.updateUserDisplayName(firstName: firstName, lastName: lastName)
            displayName = "\(firstName) \(lastName)"
            authenticationState = .authenticated
        } catch {
            errorMessage = error.localizedDescription
            isErrorAlertPresented = true
        }
    }

    private func getAuthenticationState() -> AuthenticationState {
        if user == nil {
            return .unauthenticated
        }

        if user != nil && displayName.isEmpty {
            return .needsName
        }

        return .authenticated
    }
}
