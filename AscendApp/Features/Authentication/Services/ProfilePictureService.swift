//
//  ProfilePictureService.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation

@MainActor
final class ProfilePictureService {
    static let shared = ProfilePictureService()

    private let photoRepository: any PhotoRepositoryProtocol
    private let userDataStore: any UserProfileDataStore
    private let leaderboardSyncService: (any LeaderboardProfileSyncing)?

    init(
        photoRepository: any PhotoRepositoryProtocol = FirebasePhotoRepository(),
        userDataStore: any UserProfileDataStore = UserDataRepository.shared,
        leaderboardSyncService: (any LeaderboardProfileSyncing)? = LeaderboardService.shared
    ) {
        self.photoRepository = photoRepository
        self.userDataStore = userDataStore
        self.leaderboardSyncService = leaderboardSyncService
    }

    func replaceProfilePicture(userId: String, imageData: Data) async throws -> URL {
        let previousURLString = await userDataStore.getProfilePictureURL(userId: userId)
        let previousURL = previousURLString.flatMap(URL.init(string:))
        let previousPath = previousURL.flatMap(FirebaseStoragePathResolver.storagePath(from:))

        let newPath = UserMediaStoragePath.profilePicture(userId: userId)
        let uploadedURL = try await photoRepository.upload(imageData, filename: newPath)

        do {
            try await userDataStore.updateProfilePictureURL(
                userId: userId,
                profilePictureURL: uploadedURL.absoluteString
            )
        } catch {
            try? await photoRepository.delete(path: newPath)
            throw error
        }

        if let leaderboardSyncService {
            do {
                try await leaderboardSyncService.updateProfilePictureURL(
                    userId: userId,
                    photoURL: uploadedURL
                )
            } catch {
                print("Warning: Failed to update leaderboard photo URL: \(error)")
            }
        }

        if let previousPath, previousPath != newPath {
            try? await photoRepository.delete(path: previousPath)
        } else if let previousURL, previousURL != uploadedURL {
            try? await photoRepository.delete(url: previousURL)
        }

        return uploadedURL
    }
}
