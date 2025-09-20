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

    init(_ data: [String: Any]?) {
        self.firstName = data?["firstName"] as? String
        self.lastName = data?["lastName"] as? String
        self.displayName = data?["displayName"] as? String
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
    
    func clearUserCache() {
        UserDefaults.standard.removeObject(forKey: "displayName")
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
        }
        
        return getCachedDisplayName()
    }
    
    func hasUserName(userId: String) async -> Bool {
        guard let displayName = await getDisplayName(userId: userId) else { return false }
        return !displayName.isEmpty
    }
    
    func saveUserToFirestore(userId: String, email: String?, firstName: String?, lastName: String?, displayName: String?) async throws {
        let userRef = db.collection("users").document(userId)
        
        // Check if user already exists
        let document = try await userRef.getDocument()
        let userExists = document.exists
        
        let newData = [
            "email": email ?? "",
            "firstName": firstName ?? "",
            "lastName": lastName ?? "",
            "displayName": displayName ?? ""
        ]
        
        if userExists {
            // Compare with existing data and only update changed fields
            let existingData = document.data() ?? [:]
            var changedData: [String: Any] = [:]
            
            for (key, newValue) in newData {
                let existingValue = existingData[key] as? String ?? ""
                if newValue != existingValue {
                    changedData[key] = newValue
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
}
