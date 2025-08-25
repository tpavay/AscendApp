//
//  UserDataRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/24/25.
//

import Foundation

final class UserDataRepository: Sendable {

    static let shared = UserDataRepository()

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
}
