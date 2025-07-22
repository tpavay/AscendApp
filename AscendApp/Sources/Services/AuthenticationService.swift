//
//  AuthenticationService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import Foundation
import FirebaseAuth
import Observation

// All code declared in this class will be isolated on the MainActor and therefore "isolated" to the Main Actor.
// Therefore, we do not need to declare our methods using the @MainActor macro as that has already been done at the class-level.
@MainActor
@Observable
final class AuthenticationService: Sendable {

    // Singleton authentication service
    static let shared = AuthenticationService()

    var user: User?
    var isAuthenticated: Bool {
        user != nil
    }

    private init() {
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

    func signUp(email: String, password: String, firstName: String, lastName: String) async throws {
        print("🔄 Attempting sign up for: \(email)")
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("✅ Sign up successful for: \(result.user.email ?? "Unknown")")
            self.user = result.user
            try await updateUserDisplayName(firstName: firstName, lastName: lastName)
        } catch {
            print("❌ Sign up failed: \(error.localizedDescription)")
            throw AuthenticationError.from(error)
        }
    }

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

    func deleteAccount() async throws {
        guard let current = self.user else {
            throw AuthenticationError.userNotFound
        }

        print("🔄 Attempting to delete account for: \(current.email ?? "Unknown")")
        await MainActor.run {
            current.delete()
        }
    }

    // Asynchronous function declared using the async keyword within the function signature after the function name
    @MainActor
    func updateUserDisplayName(firstName: String,
                               lastName: String) async throws {
        // 1️⃣ Get the isolated user
        guard let current = self.user else {
            throw AuthenticationError.userNotFound
        }

        // 2️⃣ Set up the change request
        let request = current.createProfileChangeRequest()
        request.displayName = "\(firstName) \(lastName)"

        // 3️⃣ Perform the non‑isolated SDK commit *and* handle its callback error
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request.commitChanges { sdkError in
                if let sdkError = sdkError {
                    continuation.resume(throwing: sdkError)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        // 4️⃣ Finally, sync your single source‑of‑truth
        //     with the fresh user object (if anything changed server‑side).
        self.user = Auth.auth().currentUser
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
