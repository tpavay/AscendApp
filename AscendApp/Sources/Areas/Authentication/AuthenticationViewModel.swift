//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
@preconcurrency import FirebaseAuth
import Observation

enum AuthenticationState {
    case authenticated
    case authenticating
    case unauthenticated
}

@Observable
class AuthenticationViewModel {
    var displayName: String = ""
    var user: User?
    var authenticationState: AuthenticationState = .unauthenticated
    var errorMessage: String?
    var isErrorAlertPresented: Bool = false

    private var authenticationService = AuthenticationService()

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
        do {
            try await authenticationService.signInWithGoogle()
        }
        catch {

        }
    }
}
