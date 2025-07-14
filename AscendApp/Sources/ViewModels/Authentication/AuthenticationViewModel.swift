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
    
    var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && 
        (isLogin || password == confirmPassword)
    }
    
    var buttonTitle: String {
        isLogin ? "Log In" : "Create Account"
    }
    
    func toggleMode() {
        isLogin.toggle()
        clearForm()
    }
    
    func authenticate() {
        guard isFormValid else {
            errorMessage = "Please fill in all fields correctly"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Simulate network call
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//            self.isLoading = false
//            if self.isLogin {
//                self.performLogin()
//            } else {
//                self.performSignUp()
//            }
//        }
    }
    
    func forgotPassword() {
        // Handle forgot password logic
        print("Forgot password for: \(email)")
    }
    
    func openTermsOfService() {
        // Handle terms of service
        print("Opening Terms of Service")
    }
    
    func openPrivacyPolicy() {
        // Handle privacy policy
        print("Opening Privacy Policy")
    }
    
    private func performLogin() {
        // Implement actual login logic
        print("Logging in with email: \(email)")
    }
    
    private func performSignUp() {
        // Implement actual sign up logic
        print("Creating account with email: \(email)")
    }
    
    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }
}
