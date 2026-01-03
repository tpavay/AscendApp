//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
import FirebaseAuth
import Observation
import PhotosUI
import SwiftUI

enum AuthenticationState {
    case authenticated
    case authenticatingWithApple
    case authenticatingWithGoogle
    case unauthenticated

    /// Shown while restoring a session on app launch (waiting for profile fetch)
    case restoringSession
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

    /// Indicates whether the profile data has been loaded from Firestore/cache after auth restore.
    /// Used to avoid showing NameInputView before we know if the user has a name.
    private(set) var isProfileLoaded: Bool = false

    private var authenticationService = AuthenticationService()
    private var photoService = PhotoService()

    init() {
        // Load cached display name immediately for UI responsiveness
        displayName = UserDataRepository.shared.getCachedDisplayName() ?? ""
        
        // Load cached profile picture URL
        if let cachedURLString = UserDataRepository.shared.getCachedProfilePictureURL() {
            customProfilePictureURL = URL(string: cachedURLString)
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
                                               self.authenticationState == .authenticatingWithApple

                    // Load cached display name immediately
                    let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName() ?? user.displayName ?? ""
                    self.displayName = cachedDisplayName

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
                        // Save/update user in Firestore first
                        try? await self.saveUserToFirestore(user: user)

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
    
    func signInWithApple() async {
        authenticationState = .authenticatingWithApple
        errorMessage = nil

        do {
            _ = try await authenticationService.signInWithApple()
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
            try await authenticationService.updateUserDisplayName(firstName: firstName, lastName: lastName)
            
            let fullDisplayName = "\(firstName) \(lastName)"
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
    
    private func saveUserToFirestore(user: User) async throws {
        // Get existing data from Firestore or use Firebase Auth data
        var firstName: String?
        var lastName: String?
        var displayNameToSave = !self.displayName.isEmpty ? self.displayName : user.displayName
        
        do {
            let userDisplayNameData = try await UserDataRepository.shared.getUserFromFirestore(userId: user.uid)
            
            // Assign existing names if we don't already have them
            firstName = userDisplayNameData.firstName
            lastName = userDisplayNameData.lastName

            // Use existing display name if we don't have a better one
            if displayNameToSave?.isEmpty == true {
                displayNameToSave = userDisplayNameData.displayName ?? 
                    (firstName != nil && lastName != nil ? "\(firstName!) \(lastName!)" : nil)
            }

        } catch {
            // If we can't fetch existing data, proceed with what we have
        }
        
        try await UserDataRepository.shared.saveUserToFirestore(
            userId: user.uid,
            email: user.email,
            firstName: firstName,
            lastName: lastName,
            displayName: displayNameToSave
        )
    }
    
    func updateProfilePicture(photoPickerItem: PhotosPickerItem) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            // Upload the photo
            let uploadedPhotos = try await photoService.uploadPhotos([photoPickerItem])
            
            guard let uploadedPhoto = uploadedPhotos.first else {
                errorMessage = "Failed to upload photo"
                return
            }
            
            // Save the URL to Firestore user document
            try await UserDataRepository.shared.updateProfilePictureURL(
                userId: user.uid,
                profilePictureURL: uploadedPhoto.url.absoluteString
            )
            
            // Update the local state
            customProfilePictureURL = uploadedPhoto.url
            
            // Update all leaderboard entries with the new photo URL
            do {
                try await LeaderboardService.shared.updateProfilePictureURL(
                    userId: user.uid,
                    photoURL: uploadedPhoto.url
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
            let filename = "profile_pictures/\(user.uid)_\(UUID().uuidString).jpg"
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
    
    func updateDisplayName(_ newDisplayName: String) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        let trimmedName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return
        }
        
        do {
            // Update local state immediately for responsive UI
            displayName = trimmedName
            
            // Save to Firestore user document
            try await UserDataRepository.shared.updateDisplayName(
                userId: user.uid,
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
            
        } catch {
            errorMessage = "Failed to update display name: \(error.localizedDescription)"
        }
    }
}
