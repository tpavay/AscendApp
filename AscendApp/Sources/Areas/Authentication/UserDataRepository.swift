//
//  UserDataRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/24/25.
//

import Foundation
@preconcurrency import FirebaseFirestore

final class UserDataRepository: Sendable {

    static let shared = UserDataRepository()
    let db = Firestore.firestore()

    private init() {}

    func saveUsername(firstName: String, lastName: String) {
        UserDefaults.standard.set(firstName, forKey: "userFirstName")
        UserDefaults.standard.set(lastName, forKey: "userLastName")

        let displayName = firstName + " " + lastName
        UserDefaults.standard.set(displayName, forKey: "displayName")
        
        // Force synchronization to disk to prevent data loss
        UserDefaults.standard.synchronize()
    }
    
    func getDisplayName() -> String? {
        return UserDefaults.standard.string(forKey: "displayName")
    }
    
    func getFirstName() -> String? {
        return UserDefaults.standard.string(forKey: "userFirstName")
    }
    
    func getLastName() -> String? {
        return UserDefaults.standard.string(forKey: "userLastName")
    }
    
    func hasUserName() -> Bool {
        return getDisplayName() != nil && !getDisplayName()!.isEmpty
    }
    
    func saveUserToFirestore(userId: String, email: String?, firstName: String?, lastName: String?, displayName: String?) async throws {
        let userData: [String: Any] = [
            "email": email ?? "",
            "firstName": firstName ?? "",
            "lastName": lastName ?? "",
            "displayName": displayName ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("users").document(userId).setData(userData, merge: true)
    }
}
