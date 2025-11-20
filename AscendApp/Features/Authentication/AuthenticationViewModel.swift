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
    var customProfilePictureURL: URL?

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
                    // Update authentication state immediately for responsive UI
                    let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName() ?? user.displayName ?? ""
                    self.displayName = cachedDisplayName
                    self.authenticationState = self.getAuthenticationState()
                    
                    // Handle Firestore operations in background
                    Task {
                        // Save/update user in Firestore first
                        try? await self.saveUserToFirestore(user: user)
                        
                        // Then fetch the latest display name from Firestore
                        if let firestoreDisplayName = await UserDataRepository.shared.getDisplayName(userId: user.uid) {
                            await MainActor.run {
                                // Only update if different from what we currently have
                                if self.displayName != firestoreDisplayName {
                                    self.displayName = firestoreDisplayName
                                    self.authenticationState = self.getAuthenticationState()
                                }
                            }
                        }
                        
                        // Fetch custom profile picture URL from Firestore
                        if let profilePictureURLString = await UserDataRepository.shared.getProfilePictureURL(userId: user.uid) {
                            await MainActor.run {
                                self.customProfilePictureURL = URL(string: profilePictureURLString)
                            }
                        }
                    }
                } else {
                    // User signed out
                    self.displayName = ""
                    self.customProfilePictureURL = nil
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
        } catch {
            // Don't show error for user cancellation
            if error is CancellationError {
                // User canceled - just reset state without showing error
                authenticationState = .unauthenticated
            } else {
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
        } catch {
            // Don't show error for user cancellation
            if error is CancellationError {
                // User canceled - just reset state without showing error
                authenticationState = .unauthenticated
            } else {
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

        // Check if we have a display name (from Firestore, cache, or Firebase Auth)
        if displayName.isEmpty {
            return .needsName
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
}
