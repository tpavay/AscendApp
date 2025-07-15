//
//  AuthenticationService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import Foundation
import FirebaseAuth
import Observation

@Observable
class AuthenticationService {
    var user: User?
    var isAuthenticated: Bool {
        user != nil
    }

    init() {
        // Listen for authentication state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                print("✅ User signed in: \(user.email ?? "Unknown")")
            } else {
                print("❌ User signed out")
            }
            self?.user = user
        }
    }

    @MainActor
    func signUp(email: String, password: String) async throws {
        print("🔄 Attempting sign up for: \(email)")
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("✅ Sign up successful for: \(result.user.email ?? "Unknown")")
            self.user = result.user
        } catch {
            print("❌ Sign up failed: \(error.localizedDescription)")
            throw AuthenticationError.from(error)
        }
    }

    @MainActor
    func signIn(email: String, password: String) async throws {
        print("🔄 Attempting sign in for: \(email)")
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("✅ Sign in successful for: \(result.user.email ?? "Unknown")")
            self.user = result.user
        } catch {
            print("❌ Sign in failed: \(error.localizedDescription)")
            throw AuthenticationError.from(error)
        }
    }

    @MainActor
    func signOut() throws {
        print("🔄 Attempting sign out")
        do {
            try Auth.auth().signOut()
            print("✅ Sign out successful")
            self.user = nil
        } catch {
            print("❌ Sign out failed: \(error.localizedDescription)")
            throw AuthenticationError.from(error)
        }
    }

    @MainActor
    func resetPassword(email: String) async throws {
        print("🔄 Attempting password reset for: \(email)")
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            print("✅ Password reset email sent to: \(email)")
        } catch {
            print("❌ Password reset failed: \(error.localizedDescription)")
            throw AuthenticationError.from(error)
        }
    }

    @MainActor
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.userNotFound
        }

        print("🔄 Attempting to delete account for: \(user.email ?? "Unknown")")
        do {
            try await user.delete()
            print("✅ Account deleted successfully")
            self.user = nil
        } catch {
            print("❌ Account deletion failed: \(error.localizedDescription)")
            throw AuthenticationError.from(error)
        }
    }
}

// MARK: - Authentication Errors
enum AuthenticationError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case userNotFound
    case wrongPassword
    case networkError
    case tooManyRequests
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .weakPassword:
            return "Password should be at least 6 characters long."
        case .emailAlreadyInUse:
            return "An account with this email already exists."
        case .userNotFound:
            return "No account found with this email."
        case .wrongPassword:
            return "Incorrect password. Please try again."
        case .networkError:
            return "Network error. Please check your connection."
        case .tooManyRequests:
            return "Too many failed attempts. Please try again later."
        case .unknown(let message):
            return message
        }
    }

    static func from(_ error: Error) -> AuthenticationError {
        guard let authError = error as NSError? else {
            return .unknown(error.localizedDescription)
        }

        guard let authErrorCode = AuthErrorCode(rawValue: authError.code) else {
            return .unknown(error.localizedDescription)
        }

        switch authErrorCode {
        case .invalidEmail:
            return .invalidEmail
        case .weakPassword:
            return .weakPassword
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .userNotFound:
            return .userNotFound
        case .wrongPassword:
            return .wrongPassword
        case .networkError:
            return .networkError
        case .tooManyRequests:
            return .tooManyRequests
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
