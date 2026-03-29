//
//  UserProfileDataStore.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation

@MainActor
protocol UserProfileDataStore: AnyObject {
    func getProfilePictureURL(userId: String) async -> String?
    func updateProfilePictureURL(userId: String, profilePictureURL: String) async throws
}
