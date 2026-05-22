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
    let age: Int?
    let gender: String?

    init(_ data: [String: Any]?) {
        self.firstName = data?["firstName"] as? String
        self.lastName = data?["lastName"] as? String
        self.displayName = data?["displayName"] as? String
        self.profilePictureURL = data?["profilePictureURL"] as? String
        if let age = data?["age"] as? Int {
            self.age = age
        } else if let age = data?["age"] as? NSNumber {
            self.age = age.intValue
        } else {
            self.age = nil
        }
        self.gender = data?["gender"] as? String
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
    
    func saveUserToFirestore(
        userId: String,
        email: String?,
        firstName: String?,
        lastName: String?,
        displayName: String?,
        profilePictureURL: String? = nil,
        age: Int? = nil,
        gender: String? = nil
    ) async throws {
        let userRef = db.collection("users").document(userId)
        
        // Check if user already exists
        let document = try await userRef.getDocument()
        let userExists = document.exists
        
        if userExists {
            var newData: [String: Any] = [:]

            if let email {
                newData["email"] = email
            }

            if let firstName {
                newData["firstName"] = firstName
            }

            if let lastName {
                newData["lastName"] = lastName
            }

            if let displayName {
                newData["displayName"] = displayName
            }

            if let profilePictureURL {
                newData["profilePictureURL"] = profilePictureURL
            }

            if let age {
                newData["age"] = age
            }

            if let gender {
                newData["gender"] = gender
            }

            // Compare with existing data and only update changed fields
            let existingData = document.data() ?? [:]
            var changedData: [String: Any] = [:]
            
            for (key, newValue) in newData {
                if let newStringValue = newValue as? String {
                    let existingValue = existingData[key] as? String ?? ""
                    if newStringValue != existingValue {
                        changedData[key] = newValue
                    }
                } else if let newIntValue = newValue as? Int {
                    let existingValue = (existingData[key] as? Int) ?? (existingData[key] as? NSNumber)?.intValue
                    if existingValue != newIntValue {
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
            var userData: [String: Any] = [
                "email": email ?? "",
                "firstName": firstName ?? "",
                "lastName": lastName ?? "",
                "displayName": displayName ?? ""
            ]

            if let profilePictureURL {
                userData["profilePictureURL"] = profilePictureURL
            }

            if let age {
                userData["age"] = age
            }

            if let gender {
                userData["gender"] = gender
            }

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
    
    func updateDisplayName(userId: String, email: String? = nil, displayName: String) async throws {
        let userRef = db.collection("users").document(userId)

        let document = try await userRef.getDocument()
        if document.exists {
            try await userRef.setData([
                "displayName": displayName,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await saveUserToFirestore(
                userId: userId,
                email: email,
                firstName: nil,
                lastName: nil,
                displayName: displayName
            )
        }
        
        cacheDisplayName(displayName)
    }

    func updateOnboardingProfile(
        userId: String,
        email: String? = nil,
        displayName: String,
        age: Int,
        gender: ProfileGender
    ) async throws {
        let userRef = db.collection("users").document(userId)

        let document = try await userRef.getDocument()
        if document.exists {
            try await userRef.setData([
                "displayName": displayName,
                "age": age,
                "gender": gender.rawValue,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await saveUserToFirestore(
                userId: userId,
                email: email,
                firstName: nil,
                lastName: nil,
                displayName: displayName,
                age: age,
                gender: gender.rawValue
            )
        }

        cacheDisplayName(displayName)
    }

}
