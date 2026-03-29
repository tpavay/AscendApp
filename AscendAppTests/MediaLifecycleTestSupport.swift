//
//  MediaLifecycleTestSupport.swift
//  AscendAppTests
//
//  Created by Codex on 3/29/26.
//

import Foundation
import FirebaseStorage
import SwiftData
@testable import AscendApp

enum TestMediaLifecycleError: Error, Equatable, Sendable {
    case uploadFailed
    case deleteFailed
    case firestoreUpdateFailed
}

extension PhotoDeletionConfig {
    static let test = PhotoDeletionConfig(
        maxRetries: 1,
        initialDelaySeconds: 0,
        backoffMultiplier: 1,
        timeoutSeconds: 0.05
    )
}

enum MediaLifecycleTestSupport {
    @MainActor
    static func makeModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            PendingMediaUpload.self,
            configurations: configuration
        )
    }

    static func makeDownloadURL(path: String) -> URL {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/ascend-test/o/\(encodedPath)?alt=media&token=test-token")!
    }
}

actor MockPhotoRepository: PhotoRepositoryProtocol {
    enum DeleteBehavior: Sendable {
        case succeed
        case fail(TestMediaLifecycleError)
        case objectNotFound
    }

    var uploadResult: Result<URL, TestMediaLifecycleError>
    var deleteBehavior: DeleteBehavior

    private var uploadedFilenames: [String] = []
    private var deletedPaths: [String] = []
    private var deletedURLs: [URL] = []

    init(
        uploadURL: URL = URL(string: "https://example.com/uploaded.jpg")!,
        deleteBehavior: DeleteBehavior = .succeed
    ) {
        self.uploadResult = .success(uploadURL)
        self.deleteBehavior = deleteBehavior
    }

    func upload(_ data: Data, filename: String) async throws -> URL {
        uploadedFilenames.append(filename)
        switch uploadResult {
        case .success(let url):
            return url
        case .failure(let error):
            throw error
        }
    }

    func delete(url: URL) async throws {
        deletedURLs.append(url)
        try throwIfNeeded()
    }

    func delete(path: String) async throws {
        deletedPaths.append(path)
        try throwIfNeeded()
    }

    func recordedUploadFilenames() -> [String] {
        uploadedFilenames
    }

    func recordedDeletedPaths() -> [String] {
        deletedPaths
    }

    func recordedDeletedURLs() -> [URL] {
        deletedURLs
    }

    private func throwIfNeeded() throws {
        switch deleteBehavior {
        case .succeed:
            return
        case .fail(let error):
            throw error
        case .objectNotFound:
            throw NSError(
                domain: StorageErrorDomain,
                code: StorageErrorCode.objectNotFound.rawValue
            )
        }
    }
}

@MainActor
final class MockPendingUploadManager: PendingUploadManaging {
    private(set) var cancelledWorkoutIds: [UUID] = []

    func cancelUploads(for workoutId: UUID, modelContext: ModelContext) async {
        cancelledWorkoutIds.append(workoutId)
    }
}

@MainActor
final class MockUserProfileDataStore: UserProfileDataStore {
    var profilePictureURL: String?
    var updateError: TestMediaLifecycleError?
    private(set) var updatedUserIds: [String] = []
    private(set) var updatedProfilePictureURLs: [String] = []

    init(profilePictureURL: String? = nil, updateError: TestMediaLifecycleError? = nil) {
        self.profilePictureURL = profilePictureURL
        self.updateError = updateError
    }

    func getProfilePictureURL(userId: String) async -> String? {
        profilePictureURL
    }

    func updateProfilePictureURL(userId: String, profilePictureURL: String) async throws {
        if let updateError {
            throw updateError
        }

        updatedUserIds.append(userId)
        updatedProfilePictureURLs.append(profilePictureURL)
        self.profilePictureURL = profilePictureURL
    }
}

@MainActor
final class MockLeaderboardProfileSyncService: LeaderboardProfileSyncing {
    private(set) var updatedUserIds: [String] = []
    private(set) var updatedPhotoURLs: [URL?] = []

    func updateProfilePictureURL(userId: String, photoURL: URL?) async throws {
        updatedUserIds.append(userId)
        updatedPhotoURLs.append(photoURL)
    }
}
