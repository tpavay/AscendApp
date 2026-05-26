//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
import FirebaseAuth
import FirebaseCore
import Observation
import PhotosUI
import SwiftUI

enum AuthenticationState {
    case authenticated
    case authenticatingWithApple
    case authenticatingWithGoogle
    case authenticatingWithInternalQA
    case unauthenticated

    /// Shown while restoring a session on app launch (waiting for profile fetch)
    case restoringSession

    var isAuthenticating: Bool {
        switch self {
        case .authenticatingWithApple, .authenticatingWithGoogle, .authenticatingWithInternalQA:
            return true
        case .authenticated, .unauthenticated, .restoringSession:
            return false
        }
    }
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
    var customProfilePictureURL: URL?
    private(set) var lastUsedProvider: AuthProviderKind?

    /// Indicates whether the profile data has been loaded from Firestore/cache after auth restore.
    /// Used to avoid showing authenticated UI before profile state is known.
    private(set) var isProfileLoaded: Bool = false

    private var authenticationService = AuthenticationService()
    private let accountSessionStore = AccountSessionStore.shared

    init() {
        lastUsedProvider = accountSessionStore.lastUsedProvider

        // Load cached display name immediately for UI responsiveness
        displayName = UserDataRepository.shared.getCachedDisplayName() ?? ""
        
        // Load cached profile picture URL
        if let cachedURLString = UserDataRepository.shared.getCachedProfilePictureURL() {
            customProfilePictureURL = URL(string: cachedURLString)
        }

        if let currentUser = Auth.auth().currentUser {
            user = currentUser
            photoURL = currentUser.photoURL
            authenticationState = .restoringSession
        }
        
        registerAuthStateHandler()
    }
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    func registerAuthStateHandler() {
        if authStateHandle == nil {
            authStateHandle = Auth.auth().addStateDidChangeListener({ auth, user in
                self.user = user
                self.photoURL = user?.photoURL ?? URL(string: "")

                if let user = user {
                    // Set telemetry user ID and log session restored
                    TelemetryManager.shared.setUserId(user.uid)
                    TelemetryManager.shared.log(.authSessionRestored)

                    // Check if we're in an interactive sign-in flow (already showing progress)
                    let isInteractiveSignIn = self.authenticationState == .authenticatingWithGoogle ||
                                               self.authenticationState == .authenticatingWithApple ||
                                               self.authenticationState == .authenticatingWithInternalQA

                    // Load cached display name immediately
                    let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName() ?? ""
                    self.displayName = cachedDisplayName
                    let shouldSaveInitialUserRecord = !isInteractiveSignIn || !cachedDisplayName.isEmpty

                    // If we have a cached name, we can show authenticated immediately
                    // Otherwise, show restoring session while we fetch from Firestore
                    if !cachedDisplayName.isEmpty {
                        self.isProfileLoaded = true
                        self.authenticationState = .authenticated
                    } else if isInteractiveSignIn {
                        // Interactive sign-in: set authenticated immediately even without display name
                        self.authenticationState = .authenticated
                    } else {
                        // Cold launch without cached name: show restoring session
                        self.isProfileLoaded = false
                        self.authenticationState = .restoringSession
                    }

                    // Handle Firestore operations in background
                    Task {
                        // Avoid writing a provider-derived or empty display name during new sign-up.
                        // The post-auth name step creates the profile document with the user's chosen name.
                        if shouldSaveInitialUserRecord {
                            try? await self.saveUserToFirestore(user: user)
                        }

                        // Fetch the authoritative display name from Firestore
                        let firestoreDisplayName = await UserDataRepository.shared.getDisplayName(userId: user.uid)

                        // Fetch custom profile picture URL from Firestore
                        let profilePictureURLString = await UserDataRepository.shared.getProfilePictureURL(userId: user.uid)

                        await MainActor.run {
                            // Update display name if we got one from Firestore
                            if let firestoreDisplayName, !firestoreDisplayName.isEmpty {
                                self.displayName = firestoreDisplayName
                            }

                            // Update profile picture URL
                            if let profilePictureURLString {
                                self.customProfilePictureURL = URL(string: profilePictureURLString)
                            }

                            // Now that profile is loaded, evaluate the final auth state
                            self.isProfileLoaded = true
                            let finalState = self.getAuthenticationState()
                            self.authenticationState = finalState

                            // Log the outcome for debugging
                            TelemetryManager.shared.log(.authProfileLoaded)
                        }
                    }
                } else {
                    // User signed out - reset all state
                    TelemetryManager.shared.log(.authSignOut)
                    TelemetryManager.shared.clearUserId()

                    self.displayName = ""
                    self.customProfilePictureURL = nil
                    self.isProfileLoaded = false
                    self.authenticationState = .unauthenticated
                    UserDataRepository.shared.clearUserCache()
                }
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
            recordSuccessfulSignIn(provider: .google)
            TelemetryManager.shared.log(.authInteractiveSignInSuccess)
        } catch {
            // Don't show error for user cancellation
            if error is CancellationError {
                // User canceled - just reset state without showing error
                authenticationState = .unauthenticated
            } else {
                TelemetryManager.shared.log(.authSignInFailed)
                TelemetryManager.shared.recordError(error, context: .auth, code: "google_sign_in_failed", additionalInfo: ["provider": "google"])
                errorMessage = error.localizedDescription
                authenticationState = .unauthenticated
            }
        }
    }

    func signInWithInternalQA(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard InternalQASignInAvailability.isEnabled(projectID: FirebaseApp.app()?.options.projectID) else {
            errorMessage = "Internal QA sign-in is unavailable in this build."
            authenticationState = .unauthenticated
            return
        }

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter the internal QA email address."
            authenticationState = .unauthenticated
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Enter the internal QA password."
            authenticationState = .unauthenticated
            return
        }

        authenticationState = .authenticatingWithInternalQA
        errorMessage = nil

        do {
            _ = try await authenticationService.signInWithEmail(email: trimmedEmail, password: password)
            recordSuccessfulSignIn(provider: .internalQA)
            TelemetryManager.shared.log(.authInteractiveSignInSuccess)
        } catch {
            TelemetryManager.shared.log(.authSignInFailed)
            TelemetryManager.shared.recordError(
                error,
                context: .auth,
                code: "internal_qa_sign_in_failed",
                additionalInfo: ["provider": "internal_qa"]
            )
            errorMessage = error.localizedDescription
            authenticationState = .unauthenticated
        }
    }
    
    func signInWithApple() async {
        authenticationState = .authenticatingWithApple
        errorMessage = nil

        do {
            _ = try await authenticationService.signInWithApple()
            recordSuccessfulSignIn(provider: .apple)
            TelemetryManager.shared.log(.authInteractiveSignInSuccess)
        } catch {
            // Don't show error for user cancellation
            if error is CancellationError {
                // User canceled - just reset state without showing error
                authenticationState = .unauthenticated
            } else {
                TelemetryManager.shared.log(.authSignInFailed)
                TelemetryManager.shared.recordError(error, context: .auth, code: "apple_sign_in_failed", additionalInfo: ["provider": "apple"])
                errorMessage = error.localizedDescription
                authenticationState = .unauthenticated
            }
        }
    }

    func setDisplayName(firstName: String, lastName: String) async {
        do {
            let fullDisplayName = "\(firstName) \(lastName)"
            try await authenticationService.updateUserDisplayName(displayName: fullDisplayName)
            displayName = fullDisplayName
            
            // Cache display name for immediate UI updates
            UserDataRepository.shared.cacheDisplayName(fullDisplayName)
            
            // Save updated user info to Firestore with individual names
            if let user = user {
                try await UserDataRepository.shared.saveUserToFirestore(
                    userId: user.uid,
                    email: user.email,
                    firstName: firstName,
                    lastName: lastName,
                    displayName: fullDisplayName
                )
            }
            
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

        return .authenticated
    }

    private func recordSuccessfulSignIn(provider: AuthProviderKind) {
        accountSessionStore.recordSuccessfulSignIn(provider: provider)
        lastUsedProvider = provider
    }
    
    private func saveUserToFirestore(user: User) async throws {
        let existingData = try? await UserDataRepository.shared.getUserFromFirestore(userId: user.uid)
        
        try await UserDataRepository.shared.saveUserToFirestore(
            userId: user.uid,
            email: user.email,
            firstName: existingData?.firstName,
            lastName: existingData?.lastName,
            displayName: existingData?.displayName,
            age: existingData?.age,
            gender: existingData?.gender
        )
    }
    
    func updateProfilePicture(photoPickerItem: PhotosPickerItem) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            guard let imageData = try await photoPickerItem.loadTransferable(type: Data.self) else {
                errorMessage = "Failed to upload photo"
                return
            }

            let filename = "users/\(user.uid)/profile_pictures/\(UUID().uuidString).jpg"
            let photoRepo = FirebasePhotoRepository()
            let uploadedURL = try await photoRepo.upload(imageData, filename: filename)

            try await UserDataRepository.shared.updateProfilePictureURL(
                userId: user.uid,
                profilePictureURL: uploadedURL.absoluteString
            )
            
            // Update the local state
            customProfilePictureURL = uploadedURL
            
            // Update all leaderboard entries with the new photo URL
            do {
                try await LeaderboardService.shared.updateProfilePictureURL(
                    userId: user.uid,
                    photoURL: uploadedURL
                )
            } catch {
                // Don't fail the whole operation if leaderboard update fails
                print("Warning: Failed to update leaderboard photo URL: \(error)")
            }
            
        } catch {
            errorMessage = "Failed to update profile picture: \(error.localizedDescription)"
        }
    }
    
    func updateProfilePictureWithData(imageData: Data) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            // Upload the photo data directly
            let filename = "users/\(user.uid)/profile_pictures/\(UUID().uuidString).jpg"
            let photoRepo = FirebasePhotoRepository()
            let uploadedURL = try await photoRepo.upload(imageData, filename: filename)
            
            // Save the URL to Firestore user document
            try await UserDataRepository.shared.updateProfilePictureURL(
                userId: user.uid,
                profilePictureURL: uploadedURL.absoluteString
            )
            
            // Update the local state
            customProfilePictureURL = uploadedURL
            
            // Update all leaderboard entries with the new photo URL
            do {
                try await LeaderboardService.shared.updateProfilePictureURL(
                    userId: user.uid,
                    photoURL: uploadedURL
                )
            } catch {
                // Don't fail the whole operation if leaderboard update fails
                print("Warning: Failed to update leaderboard photo URL: \(error)")
            }
            
        } catch {
            errorMessage = "Failed to update profile picture: \(error.localizedDescription)"
        }
    }
    
    var displayPhotoURL: URL? {
        // Prioritize custom profile picture, then fall back to OAuth provider photo
        return customProfilePictureURL ?? photoURL
    }
    
    @discardableResult
    func updateDisplayName(_ newDisplayName: String) async -> Bool {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return false
        }
        
        let trimmedName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return false
        }
        
        let previousDisplayName = displayName

        do {
            // Update local state immediately for responsive UI
            displayName = trimmedName

            try await authenticationService.updateUserDisplayName(displayName: trimmedName)
            
            // Save to Firestore user document
            try await UserDataRepository.shared.updateDisplayName(
                userId: user.uid,
                email: user.email,
                displayName: trimmedName
            )
            
            // Update all leaderboard entries with the new display name
            do {
                try await LeaderboardService.shared.updateDisplayName(
                    userId: user.uid,
                    displayName: trimmedName
                )
            } catch {
                // Don't fail the whole operation if leaderboard update fails
                print("Warning: Failed to update leaderboard display name: \(error)")
            }

            return true
            
        } catch {
            displayName = previousDisplayName
            errorMessage = "Failed to update display name: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateOnboardingProfile(displayName newDisplayName: String, age: Int, gender: ProfileGender) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        let trimmedName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return false
        }

        guard (13...120).contains(age) else {
            errorMessage = "Enter an age from 13 to 120"
            return false
        }

        let previousDisplayName = displayName

        do {
            displayName = trimmedName

            try await authenticationService.updateUserDisplayName(displayName: trimmedName)

            try await UserDataRepository.shared.updateOnboardingProfile(
                userId: user.uid,
                email: user.email,
                displayName: trimmedName,
                age: age,
                gender: gender
            )

            do {
                try await LeaderboardService.shared.updateDisplayName(
                    userId: user.uid,
                    displayName: trimmedName
                )
            } catch {
                print("Warning: Failed to update leaderboard display name: \(error)")
            }

            return true
        } catch {
            displayName = previousDisplayName
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            return false
        }
    }
}
