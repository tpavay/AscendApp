//
//  ProfilePictureServiceTests.swift
//  AscendAppTests
//
//  Created by Codex on 3/29/26.
//

import Foundation
import Testing
@testable import AscendApp

@MainActor
struct ProfilePictureServiceTests {
    @Test
    func replaceProfilePictureDeletesPreviousScopedObjectAfterSuccessfulSwap() async throws {
        let uploadedURL = MediaLifecycleTestSupport.makeDownloadURL(
            path: "users/test-user/profile_pictures/new-avatar.jpg"
        )
        let repository = MockPhotoRepository(uploadURL: uploadedURL)
        let userDataStore = MockUserProfileDataStore(
            profilePictureURL: MediaLifecycleTestSupport.makeDownloadURL(
                path: "users/test-user/profile_pictures/old-avatar.jpg"
            ).absoluteString
        )
        let leaderboardSync = MockLeaderboardProfileSyncService()
        let service = ProfilePictureService(
            photoRepository: repository,
            userDataStore: userDataStore,
            leaderboardSyncService: leaderboardSync
        )

        let result = try await service.replaceProfilePicture(
            userId: "test-user",
            imageData: Data([0x01, 0x02, 0x03])
        )

        #expect(result == uploadedURL)
        #expect(userDataStore.updatedUserIds == ["test-user"])
        #expect(userDataStore.updatedProfilePictureURLs == [uploadedURL.absoluteString])
        #expect(leaderboardSync.updatedUserIds == ["test-user"])
        #expect(leaderboardSync.updatedPhotoURLs == [uploadedURL])

        let uploadedFilenames = await repository.recordedUploadFilenames()
        #expect(uploadedFilenames.count == 1)
        #expect(uploadedFilenames.first?.hasPrefix("users/test-user/profile_pictures/") == true)

        let deletedPaths = await repository.recordedDeletedPaths()
        #expect(deletedPaths == ["users/test-user/profile_pictures/old-avatar.jpg"])
    }

    @Test
    func replaceProfilePictureCleansUpNewUploadWhenFirestoreUpdateFails() async throws {
        let uploadedURL = MediaLifecycleTestSupport.makeDownloadURL(
            path: "users/test-user/profile_pictures/new-avatar.jpg"
        )
        let repository = MockPhotoRepository(uploadURL: uploadedURL)
        let userDataStore = MockUserProfileDataStore(updateError: .firestoreUpdateFailed)
        let leaderboardSync = MockLeaderboardProfileSyncService()
        let service = ProfilePictureService(
            photoRepository: repository,
            userDataStore: userDataStore,
            leaderboardSyncService: leaderboardSync
        )

        do {
            _ = try await service.replaceProfilePicture(
                userId: "test-user",
                imageData: Data([0x0A, 0x0B])
            )
            Issue.record("Expected profile picture replacement to fail when Firestore update fails.")
        } catch {
            let uploadedFilenames = await repository.recordedUploadFilenames()
            let deletedPaths = await repository.recordedDeletedPaths()

            #expect(uploadedFilenames.count == 1)
            #expect(deletedPaths == uploadedFilenames)
            #expect(leaderboardSync.updatedUserIds.isEmpty)
            #expect(userDataStore.updatedUserIds.isEmpty)
        }
    }
}
