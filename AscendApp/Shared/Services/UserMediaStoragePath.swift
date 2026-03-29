//
//  UserMediaStoragePath.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation

enum UserMediaStoragePath {
    static func photo(userId: String, fileId: UUID = UUID()) -> String {
        "users/\(userId)/photos/\(fileId.uuidString).jpg"
    }

    static func video(
        userId: String,
        fileId: UUID = UUID(),
        fileExtension: String
    ) -> String {
        "users/\(userId)/videos/\(fileId.uuidString).\(sanitizedExtension(fileExtension))"
    }

    static func profilePicture(
        userId: String,
        fileId: UUID = UUID(),
        fileExtension: String = "jpg"
    ) -> String {
        "users/\(userId)/profile_pictures/\(fileId.uuidString).\(sanitizedExtension(fileExtension))"
    }

    private static func sanitizedExtension(_ fileExtension: String) -> String {
        let trimmed = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return trimmed.isEmpty ? "jpg" : trimmed
    }
}
