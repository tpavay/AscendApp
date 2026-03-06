//
//  UserDataRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/24/25.
//

import Foundation
@preconcurrency import FirebaseFirestore

struct UserDisplayNameData: Sendable {
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let profilePictureURL: String?

    init(_ data: [String: Any]?) {
        self.firstName = data?["firstName"] as? String
        self.lastName = data?["lastName"] as? String
        self.displayName = data?["displayName"] as? String
        self.profilePictureURL = data?["profilePictureURL"] as? String
    }
}

final class UserDataRepository: Sendable {

    static let shared = UserDataRepository()
    let db = Firestore.firestore()

    private init() {}

    func cacheDisplayName(_ displayName: String) {
        UserDefaults.standard.set(displayName, forKey: "displayName")
        UserDefaults.standard.synchronize()
    }
    
    func getCachedDisplayName() -> String? {
        return UserDefaults.standard.string(forKey: "displayName")
    }
    
    func cacheProfilePictureURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: "profilePictureURL")
        UserDefaults.standard.synchronize()
    }
    
    func getCachedProfilePictureURL() -> String? {
        return UserDefaults.standard.string(forKey: "profilePictureURL")
    }
    
    func clearUserCache() {
        UserDefaults.standard.removeObject(forKey: "displayName")
        UserDefaults.standard.removeObject(forKey: "profilePictureURL")
        UserDefaults.standard.synchronize()
    }
    
    func getUserFromFirestore(userId: String) async throws -> UserDisplayNameData {
        let document = try await db.collection("users").document(userId).getDocument()

        let userDisplayNameData = UserDisplayNameData(document.data())
        return userDisplayNameData
    }
    
    func getDisplayName(userId: String) async -> String? {
        do {
            let userData = try await getUserFromFirestore(userId: userId)
            let displayName = userData.displayName ?? ""
            if !displayName.isEmpty {
                cacheDisplayName(displayName)
                return displayName
            }
        } catch {
            print("Error fetching user from Firestore: \(error)")
            TelemetryManager.shared.recordError(error, context: .firestore, code: "user_fetch_failed")
        }

        return getCachedDisplayName()
    }
    
    func hasUserName(userId: String) async -> Bool {
        guard let displayName = await getDisplayName(userId: userId) else { return false }
        return !displayName.isEmpty
    }
    
    func saveUserToFirestore(userId: String, email: String?, firstName: String?, lastName: String?, displayName: String?, profilePictureURL: String? = nil) async throws {
        let userRef = db.collection("users").document(userId)
        
        // Check if user already exists
        let document = try await userRef.getDocument()
        let userExists = document.exists
        
        var newData: [String: Any] = [
            "email": email ?? "",
            "firstName": firstName ?? "",
            "lastName": lastName ?? "",
            "displayName": displayName ?? ""
        ]
        
        // Only include profilePictureURL if it's provided
        if let profilePictureURL = profilePictureURL {
            newData["profilePictureURL"] = profilePictureURL
        }
        
        if userExists {
            // Compare with existing data and only update changed fields
            let existingData = document.data() ?? [:]
            var changedData: [String: Any] = [:]
            
            for (key, newValue) in newData {
                if let newStringValue = newValue as? String {
                    let existingValue = existingData[key] as? String ?? ""
                    if newStringValue != existingValue {
                        changedData[key] = newValue
                    }
                }
            }
            
            // Only update if data actually changed
            if !changedData.isEmpty {
                changedData["lastUpdated"] = FieldValue.serverTimestamp()
                try await userRef.setData(changedData, merge: true)
            }
        } else {
            // New user - create with all data plus timestamps
            var userData: [String: Any] = newData
            userData["createdAt"] = FieldValue.serverTimestamp()
            userData["lastUpdated"] = FieldValue.serverTimestamp()
            try await userRef.setData(userData, merge: true)
        }
    }
    
    func updateProfilePictureURL(userId: String, profilePictureURL: String) async throws {
        let userRef = db.collection("users").document(userId)
        
        try await userRef.setData([
            "profilePictureURL": profilePictureURL,
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
        
        cacheProfilePictureURL(profilePictureURL)
    }
    
    func getProfilePictureURL(userId: String) async -> String? {
        do {
            let userData = try await getUserFromFirestore(userId: userId)
            if let profilePictureURL = userData.profilePictureURL, !profilePictureURL.isEmpty {
                cacheProfilePictureURL(profilePictureURL)
                return profilePictureURL
            }
        } catch {
            print("Error fetching profile picture URL from Firestore: \(error)")
            TelemetryManager.shared.recordError(error, context: .firestore, code: "profile_picture_fetch_failed")
        }

        return getCachedProfilePictureURL()
    }
    
    func updateDisplayName(userId: String, displayName: String) async throws {
        let userRef = db.collection("users").document(userId)
        
        try await userRef.setData([
            "displayName": displayName,
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
        
        cacheDisplayName(displayName)
    }

    func upsertOnboardingProfile(userId: String, draft: OnboardingDraft) async throws {
        let userRef = db.collection("users").document(userId)

        let profileData: [String: Any] = [
            "measurementSystem": draft.measurementSystem.rawValue,
            "fitnessLevel": draft.fitnessLevel.rawValue,
            "dateOfBirth": Timestamp(date: draft.dateOfBirth),
            "gender": draft.gender.rawValue,
            "heightCm": draft.heightCm,
            "bodyWeightKg": draft.bodyWeightKg,
            "healthKitOptIn": draft.healthKitOptIn,
            "notificationOptIn": draft.notificationOptIn,
            "location": [
                "country": draft.locationSummary.country,
                "region": draft.locationSummary.region,
                "city": draft.locationSummary.city
            ]
        ]

        let onboardingData: [String: Any] = [
            "version": 2,
            "completedAt": FieldValue.serverTimestamp()
        ]

        try await userRef.setData([
            "profile": profileData,
            "onboarding": onboardingData,
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func fetchOnboardingDraft(userId: String) async throws -> OnboardingDraft? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        guard let data = snapshot.data(),
              let profile = data["profile"] as? [String: Any] else {
            return nil
        }

        var draft = OnboardingDraft.default

        if let rawMeasurementSystem = profile["measurementSystem"] as? String,
           let measurementSystem = MeasurementSystem(rawValue: rawMeasurementSystem) {
            draft.measurementSystem = measurementSystem
        }

        if let rawFitnessLevel = profile["fitnessLevel"] as? String,
           let fitnessLevel = FitnessLevel(rawValue: rawFitnessLevel) {
            draft.fitnessLevel = fitnessLevel
        }

        if let timestamp = profile["dateOfBirth"] as? Timestamp {
            draft.dateOfBirth = timestamp.dateValue()
        }

        if let rawGender = profile["gender"] as? String,
           let gender = UserProfileGender(rawValue: rawGender) {
            draft.gender = gender
        }

        if let heightCm = profile["heightCm"] as? Double {
            draft.heightCm = heightCm
        } else if let heightCm = profile["heightCm"] as? NSNumber {
            draft.heightCm = heightCm.doubleValue
        }

        if let bodyWeightKg = profile["bodyWeightKg"] as? Double {
            draft.bodyWeightKg = bodyWeightKg
        } else if let bodyWeightKg = profile["bodyWeightKg"] as? NSNumber {
            draft.bodyWeightKg = bodyWeightKg.doubleValue
        }

        if let healthKitOptIn = profile["healthKitOptIn"] as? Bool {
            draft.healthKitOptIn = healthKitOptIn
        }

        if let notificationOptIn = profile["notificationOptIn"] as? Bool {
            draft.notificationOptIn = notificationOptIn
        }

        if let location = profile["location"] as? [String: Any] {
            draft.locationSummary = UserLocationSummary(
                country: location["country"] as? String ?? "",
                region: location["region"] as? String ?? "",
                city: location["city"] as? String ?? ""
            )
        }

        draft.currentStep = .auth
        return draft
    }
}
