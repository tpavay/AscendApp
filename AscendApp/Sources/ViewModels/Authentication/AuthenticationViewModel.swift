//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI
import Observation

@Observable
class AuthenticationViewModel {
    var email = ""
    var password = ""
    var confirmPassword = ""
    var isLogin = true
    var isLoading = false
    var errorMessage: String?

    private let authService = AuthenticationService()

    var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        email.contains("@") &&
        password.count >= 6 &&
        (isLogin || password == confirmPassword)
    }

    var buttonTitle: String {
        isLogin ? "Log In" : "Create Account"
    }

    func toggleMode() {
        isLogin.toggle()
        clearForm()
    }

    @MainActor
    func authenticate() async {
        guard isFormValid else {
            errorMessage = getValidationError()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            if isLogin {
                try await authService.signIn(email: email, password: password)
            } else {
                try await authService.signUp(email: email, password: password)
            }
            // Success - authentication state will be handled by AuthenticationService
            clearForm()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func forgotPassword() async {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email address first."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authService.resetPassword(email: email)
            errorMessage = "Password reset email sent! Check your inbox."
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func openTermsOfService() {
        // Handle terms of service
        print("Opening Terms of Service")
    }

    func openPrivacyPolicy() {
        // Handle privacy policy
        print("Opening Privacy Policy")
    }

    private func getValidationError() -> String {
        if email.isEmpty {
            return "Please enter your email address."
        }
        if !email.contains("@") {
            return "Please enter a valid email address."
        }
        if password.isEmpty {
            return "Please enter your password."
        }
        if password.count < 6 {
            return "Password must be at least 6 characters long."
        }
        if !isLogin && password != confirmPassword {
            return "Passwords do not match."
        }
        return "Please fill in all fields correctly."
    }

    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }
}
