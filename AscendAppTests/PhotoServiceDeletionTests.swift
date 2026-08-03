//
//  PhotoServiceDeletionTests.swift
//  AscendAppTests
//

import Foundation
import Testing
@testable import AscendApp

struct PhotoServiceDeletionTests {

    private static func downloadURL(objectPath: String) -> URL {
        let encoded = objectPath.replacing("/", with: "%2F")
        return URL(
            string: "https://firebasestorage.googleapis.com/v0/b/bucket.firebasestorage.app/o/"
                + "\(encoded)?alt=media&token=94f4cee6-de5e-4562-b7f8-c1cf2fbc6d44"
        )!
    }

    @Test
    func deletesAWorkoutWhoseMediaSitsAtAClosedLegacyPath() async throws {
        // storage.rules closes the flat photos/ prefix to every client, so a
        // delete there can only fail. Workout deletion aborts on any media
        // failure, so retrying it would leave a pre-migration workout that its
        // owner can never delete.
        let repo = RecordingPhotoRepository(deletionError: TestError.permissionDenied)
        let service = PhotoService(repo: repo)
        let legacy = Photo(url: Self.downloadURL(objectPath: "photos/legacy.jpg"))

        try await service.deletePhotos([legacy])

        #expect(await repo.deletedURLs.isEmpty)
    }

    @Test
    func stillDeletesOwnerScopedMediaAlongsideUnreachableMedia() async throws {
        let repo = RecordingPhotoRepository()
        let service = PhotoService(repo: repo)
        let legacy = Photo(url: Self.downloadURL(objectPath: "videos/legacy.mov"))
        let owned = Photo(url: Self.downloadURL(objectPath: "users/uid-1/photos/owned.jpg"))

        let result = await service.deletePhotosWithResult([legacy, owned])

        #expect(await repo.deletedURLs == [owned.url])
        #expect(result.failedDeletions.isEmpty)
        #expect(Set(result.successfulDeletions.map(\.url)) == [legacy.url, owned.url])
    }

    @Test
    func reportsSkippedUnreachableMediaAsADiagnostic() async throws {
        // Skipped media is counted as deleted, so without this signal a delete
        // that never happened is indistinguishable from one that did.
        let diagnostics = SpyDiagnosticsRecorder()
        let service = PhotoService(repo: RecordingPhotoRepository(), diagnostics: diagnostics)
        let legacy = Photo(url: Self.downloadURL(objectPath: "photos/legacy.jpg"))
        let owned = Photo(url: Self.downloadURL(objectPath: "users/uid-1/photos/owned.jpg"))

        _ = await service.deletePhotosWithResult([legacy, owned])

        let events = diagnostics.events
        #expect(events.count == 1)
        #expect(events.first?.name == "media_delete_skipped_closed_legacy_path")
        #expect(events.first?.details["skipped_count"] == "1")
        #expect(events.first?.details["requested_count"] == "2")
    }

    @Test
    func staysQuietWhenEveryPhotoIsReachable() async throws {
        let diagnostics = SpyDiagnosticsRecorder()
        let service = PhotoService(repo: RecordingPhotoRepository(), diagnostics: diagnostics)
        let owned = Photo(url: Self.downloadURL(objectPath: "users/uid-1/photos/owned.jpg"))

        _ = await service.deletePhotosWithResult([owned])

        #expect(diagnostics.events.isEmpty)
    }

    @Test
    func stillReportsAFailureWhenOwnerScopedMediaCannotBeDeleted() async throws {
        // Skipping unreachable media must not soften the guarantee that a real
        // cloud object is gone before the local workout is.
        let repo = RecordingPhotoRepository(deletionError: TestError.permissionDenied)
        let service = PhotoService(
            repo: repo,
            deletionConfig: PhotoDeletionConfig(
                maxRetries: 1,
                initialDelaySeconds: 0,
                backoffMultiplier: 1,
                timeoutSeconds: 5
            )
        )
        let owned = Photo(url: Self.downloadURL(objectPath: "users/uid-1/photos/owned.jpg"))

        await #expect(throws: PhotoDeletionError.self) {
            try await service.deletePhotos([owned])
        }
    }
}

private enum TestError: Error {
    case permissionDenied
}

private actor RecordingPhotoRepository: PhotoRepositoryProtocol {
    private(set) var deletedURLs: [URL] = []
    private let deletionError: (any Error)?

    init(deletionError: (any Error)? = nil) {
        self.deletionError = deletionError
    }

    func upload(_ data: Data, filename: String) async throws -> URL {
        URL(string: "https://example.com/\(filename)")!
    }

    func delete(url: URL) async throws {
        if let deletionError {
            throw deletionError
        }
        deletedURLs.append(url)
    }
}
