//
//  AccountDeletionService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftData

/// Service responsible for handling complete account deletion
/// Deletes data from: Firebase Auth, Firestore, Firebase Storage, and local SwiftData
@MainActor
final class AccountDeletionService {
    
    enum DeletionError: LocalizedError {
        case notAuthenticated
        case firestoreDeletionFailed(String)
        case storageDeletionFailed(String)
        case authDeletionFailed(String)
        case localDataDeletionFailed(String)
        case requiresRecentLogin
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to delete your account."
            case .firestoreDeletionFailed(let message):
                return "Failed to delete cloud data: \(message)"
            case .storageDeletionFailed(let message):
                return "Failed to delete stored files: \(message)"
            case .authDeletionFailed(let message):
                return "Failed to delete account: \(message)"
            case .localDataDeletionFailed(let message):
                return "Failed to delete local data: \(message)"
            case .requiresRecentLogin:
                return "For security, please sign out and sign back in, then try deleting your account again."
            }
        }
    }
    
    struct DeletionProgress {
        var currentStep: String
        var completedSteps: Int
        var totalSteps: Int
        
        var progressPercentage: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(completedSteps) / Double(totalSteps)
        }
    }
    
    private let db = Firestore.firestore()
    
    /// Performs complete account deletion
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local data deletion
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: True if deletion was successful
    func deleteAccount(
        modelContext: ModelContext,
        progressHandler: ((DeletionProgress) -> Void)? = nil
    ) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DeletionError.notAuthenticated
        }
        
        let userId = user.uid
        let totalSteps = 6
        var completedSteps = 0
        
        func updateProgress(_ step: String) {
            progressHandler?(DeletionProgress(
                currentStep: step,
                completedSteps: completedSteps,
                totalSteps: totalSteps
            ))
        }
        
        // Step 1: Delete workout photos/videos from Firebase Storage
        updateProgress("Deleting workout media...")
        try await deleteWorkoutMedia(modelContext: modelContext)
        completedSteps += 1
        
        // Step 2: Delete profile picture from Firebase Storage
        updateProgress("Deleting profile picture...")
        try await deleteProfilePicture(userId: userId)
        completedSteps += 1
        
        // Step 3: Delete Firestore leaderboard stats
        updateProgress("Deleting leaderboard data...")
        try await deleteLeaderboardStats(userId: userId)
        completedSteps += 1
        
        // Step 4: Delete Firestore user document
        updateProgress("Deleting user profile...")
        try await deleteUserDocument(userId: userId)
        completedSteps += 1
        
        // Step 5: Delete local SwiftData
        updateProgress("Deleting local data...")
        try deleteLocalData(modelContext: modelContext)
        completedSteps += 1
        
        // Step 6: Delete Firebase Auth account
        updateProgress("Deleting account...")
        do {
            try await user.delete()
        } catch let error as NSError {
            // Check if re-authentication is required
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw DeletionError.requiresRecentLogin
            }
            throw DeletionError.authDeletionFailed(error.localizedDescription)
        }
        completedSteps += 1
        
        // Clear all cached data
        clearUserDefaults()
        
        updateProgress("Account deleted successfully")
    }
    
    // MARK: - Private Deletion Methods
    
    /// Deletes all workout photos and videos from Firebase Storage
    private func deleteWorkoutMedia(modelContext: ModelContext) async throws {
        // Fetch all workouts to get their photos
        let descriptor = FetchDescriptor<Workout>()
        
        do {
            let workouts = try modelContext.fetch(descriptor)
            let photoService = PhotoService()
            
            for workout in workouts {
                if !workout.photos.isEmpty {
                    do {
                        try await photoService.deletePhotos(workout.photos)
                    } catch {
                        // Log but continue - some photos might already be deleted
                        #if DEBUG
                        print("⚠️ Could not delete some workout photos: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            throw DeletionError.storageDeletionFailed(error.localizedDescription)
        }
    }
    
    /// Deletes the user's profile picture from Firebase Storage
    private nonisolated func deleteProfilePicture(userId: String) async throws {
        // Try to delete from the profile_pictures folder
        let profilePicRef = Storage.storage().reference().child("profile_pictures")
        
        do {
            // List all files in the profile_pictures folder that match this user
            let result = try await profilePicRef.listAll()
            
            for item in result.items {
                if item.name.hasPrefix(userId) {
                    try await item.delete()
                }
            }
        } catch {
            // Profile picture might not exist, which is fine
            #if DEBUG
            print("⚠️ Could not delete profile picture: \(error)")
            #endif
        }
    }
    
    /// Deletes all leaderboard stats documents for the user from Firestore
    private func deleteLeaderboardStats(userId: String) async throws {
        do {
            let query = db.collection("leaderboard_stats")
                .whereField("userId", isEqualTo: userId)
            
            let snapshot = try await query.getDocuments()
            
            // Delete each document
            for document in snapshot.documents {
                try await document.reference.delete()
            }
        } catch {
            throw DeletionError.firestoreDeletionFailed(error.localizedDescription)
        }
    }
    
    /// Deletes the user document from Firestore
    private func deleteUserDocument(userId: String) async throws {
        do {
            try await db.collection("users").document(userId).delete()
        } catch {
            throw DeletionError.firestoreDeletionFailed(error.localizedDescription)
        }
    }
    
    /// Deletes all local SwiftData (Workouts, LeaderboardStats, PersonalRecords)
    private func deleteLocalData(modelContext: ModelContext) throws {
        do {
            // Delete all Workouts
            let workoutDescriptor = FetchDescriptor<Workout>()
            let workouts = try modelContext.fetch(workoutDescriptor)
            for workout in workouts {
                modelContext.delete(workout)
            }
            
            // Delete all LeaderboardStats
            let statsDescriptor = FetchDescriptor<LeaderboardStats>()
            let stats = try modelContext.fetch(statsDescriptor)
            for stat in stats {
                modelContext.delete(stat)
            }
            
            // Delete all PersonalRecords
            let recordsDescriptor = FetchDescriptor<PersonalRecord>()
            let records = try modelContext.fetch(recordsDescriptor)
            for record in records {
                modelContext.delete(record)
            }
            
            try modelContext.save()
        } catch {
            throw DeletionError.localDataDeletionFailed(error.localizedDescription)
        }
    }
    
    /// Clears all UserDefaults data related to the user
    private func clearUserDefaults() {
        let keysToRemove = [
            "displayName",
            "profilePictureURL",
            "preferredWorkoutMetric",
            "measurementSystem",
            "stepHeight",
            "stepsPerFloor",
            "lastHealthKitImportDate",
            "selectedTheme"
        ]
        
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        UserDefaults.standard.synchronize()
    }
}

