//
//  PhotoService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import PhotosUI
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import FirebaseAuth

actor PhotoService {
    private let repo: any PhotoRepositoryProtocol
    private let deletionConfig: PhotoDeletionConfig

    init(
        repo: any PhotoRepositoryProtocol = FirebasePhotoRepository(),
        deletionConfig: PhotoDeletionConfig = .default
    ) {
        self.repo = repo
        self.deletionConfig = deletionConfig
    }

    func uploadPhotos(_ items: [PhotosPickerItem]) async throws -> [Photo] {
        let repo = self.repo
        return try await withThrowingTaskGroup(of: Photo?.self) { group in
            for item in items {
                group.addTask {
                    // Check if it's a video
                    if let contentType = item.supportedContentTypes.first,
                       contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                        return try await self.uploadVideo(item, repo: repo)
                    } else {
                        return try await self.uploadPhoto(item, repo: repo)
                    }
                }
            }
            var out: [Photo] = []
            for try await p in group { if let p { out.append(p) } }
            return out
        }
    }
    
    /// Upload photos from SelectedPhotoItems
    func uploadSelectedPhotos(_ items: [SelectedPhotoItem]) async throws -> [Photo] {
        struct UploadResult {
            let photo: Photo?
            let itemId: UUID
        }

        // Collect all video URLs upfront for cleanup regardless of success/failure
        let videoURLsToCleanup = items.compactMap { $0.videoURL }

        // Ensure temp video files are always cleaned up
        defer {
            for videoURL in videoURLsToCleanup {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }

        let repo = self.repo
        return try await withThrowingTaskGroup(of: UploadResult.self) { group in
            for item in items {
                group.addTask {
                    if item.isVideo {
                        if let videoURL = item.videoURL {
                            let photo = try await self.uploadVideoFromURL(videoURL, duration: item.duration ?? 0, repo: repo)
                            return UploadResult(photo: photo, itemId: item.id)
                        } else {
                            let photo = try await self.uploadVideo(item.pickerItem, repo: repo)
                            return UploadResult(photo: photo, itemId: item.id)
                        }
                    } else {
                        let photo = try await self.uploadPhoto(item.pickerItem, repo: repo)
                        return UploadResult(photo: photo, itemId: item.id)
                    }
                }
            }

            var uploadedPhotosById: [UUID: Photo] = [:]

            for try await result in group {
                if let photo = result.photo {
                    uploadedPhotosById[result.itemId] = photo
                }
            }

            return items.compactMap { uploadedPhotosById[$0.id] }
        }
    }
    
    private func uploadPhoto(_ item: PhotosPickerItem, repo: any PhotoRepositoryProtocol) async throws -> Photo? {
        guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
        let filename = "users/\(try currentUserId())/photos/\(UUID().uuidString).jpg"
        let url = try await repo.upload(data, filename: filename)
        return Photo(url: url, type: .photo, duration: nil)
    }
    
    private func uploadVideo(_ item: PhotosPickerItem, repo: any PhotoRepositoryProtocol) async throws -> Photo? {
        guard let movie = try await item.loadTransferable(type: VideoPickerTransferable.self) else {
            return nil
        }
        
        // Get video duration
        let asset = AVURLAsset(url: movie.url)
        let duration = try await asset.load(.duration).seconds
        
        // Load video data
        let data = try Data(contentsOf: movie.url)
        
        // Upload with video extension
        let fileExtension = movie.url.pathExtension.isEmpty ? "mov" : movie.url.pathExtension
        let filename = "users/\(try currentUserId())/videos/\(UUID().uuidString).\(fileExtension)"
        let url = try await repo.upload(data, filename: filename)
        
        // Clean up temporary file
        try? FileManager.default.removeItem(at: movie.url)
        
        return Photo(url: url, type: .video, duration: duration)
    }
    
    /// Upload a video from a URL (used for trimmed videos)
    private func uploadVideoFromURL(_ videoURL: URL, duration: TimeInterval, repo: any PhotoRepositoryProtocol) async throws -> Photo? {
        // Load video data
        let data = try Data(contentsOf: videoURL)
        
        // Upload with video extension
        let fileExtension = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        let filename = "users/\(try currentUserId())/videos/\(UUID().uuidString).\(fileExtension)"
        let url = try await repo.upload(data, filename: filename)
        
        // Don't clean up the temporary file here - PhotoGalleryView will handle cleanup
        
        return Photo(url: url, type: .video, duration: duration)
    }

    // MARK: - Photo Deletion with Retry

    /// Deletes photos with automatic retry and timeout handling
    /// - Parameter photos: Photos to delete
    /// - Throws: PhotoDeletionError.partialFailure if any deletions fail after retries
    func deletePhotos(_ photos: [Photo]) async throws {
        let result = await deletePhotosWithResult(photos)

        if !result.allSucceeded {
            throw PhotoDeletionError.partialFailure(result: result)
        }
    }

    /// Deletes photos and returns detailed results (success/failure for each)
    /// - Parameter photos: Photos to delete
    /// - Returns: PhotoDeletionResult with successful and failed deletions
    func deletePhotosWithResult(_ photos: [Photo]) async -> PhotoDeletionResult {
        let repo = self.repo
        let config = self.deletionConfig

        return await withTaskGroup(of: (Photo, (any Error)?).self) { group in
            for photo in photos {
                group.addTask {
                    do {
                        try await self.deletePhotoWithRetry(photo, repo: repo, config: config)
                        return (photo, nil)
                    } catch {
                        return (photo, error)
                    }
                }
            }

            var successful: [Photo] = []
            var failed: [(Photo, any Error)] = []

            for await (photo, error) in group {
                if let error = error {
                    failed.append((photo, error))
                } else {
                    successful.append(photo)
                }
            }

            return PhotoDeletionResult(
                successfulDeletions: successful,
                failedDeletions: failed
            )
        }
    }

    /// Deletes a single photo with retry logic
    private func deletePhotoWithRetry(
        _ photo: Photo,
        repo: any PhotoRepositoryProtocol,
        config: PhotoDeletionConfig
    ) async throws {
        var lastError: (any Error)?
        var currentDelay = config.initialDelaySeconds

        for attempt in 0..<config.maxRetries {
            // Check cancellation BEFORE each attempt
            try Task.checkCancellation()

            do {
                try await deletePhotoWithTimeout(photo, repo: repo, timeout: config.timeoutSeconds)
                return // Success
            } catch is CancellationError {
                // Don't swallow cancellation - re-throw immediately
                throw CancellationError()
            } catch {
                lastError = error

                // Check cancellation after failure before retrying
                if Task.isCancelled { throw CancellationError() }

                // Don't wait after the last attempt
                if attempt < config.maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(currentDelay))
                    currentDelay *= config.backoffMultiplier
                }
            }
        }

        throw PhotoDeletionError.allRetriesExhausted(
            url: photo.url,
            lastError: lastError ?? NSError(domain: "PhotoService", code: -1)
        )
    }

    /// Deletes a single photo with a timeout
    private func deletePhotoWithTimeout(
        _ photo: Photo,
        repo: any PhotoRepositoryProtocol,
        timeout: Double
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Deletion task
            group.addTask {
                // Check cancellation inside task group
                try Task.checkCancellation()
                try await repo.delete(url: photo.url)
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw PhotoDeletionError.timeout(url: photo.url)
            }

            // Wait for first to complete (either deletion succeeds or timeout fires)
            do {
                try await group.next()
                group.cancelAll()
            } catch is CancellationError {
                // Preserve cancellation error
                group.cancelAll()
                throw CancellationError()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func currentUserId() throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "PhotoService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in to upload media."]
            )
        }
        return userId
    }
}
