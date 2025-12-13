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

actor PhotoService {
    private let repo: any PhotoRepositoryProtocol
    init(repo: any PhotoRepositoryProtocol = FirebasePhotoRepository()) {
        self.repo = repo
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
        let filename = "photos/\(UUID().uuidString).jpg"
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
        let filename = "videos/\(UUID().uuidString).\(fileExtension)"
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
        let filename = "videos/\(UUID().uuidString).\(fileExtension)"
        let url = try await repo.upload(data, filename: filename)
        
        // Don't clean up the temporary file here - PhotoGalleryView will handle cleanup
        
        return Photo(url: url, type: .video, duration: duration)
    }

    func deletePhotos(_ photos: [Photo]) async throws {
        let repo = self.repo
        try await withThrowingTaskGroup(of: Void.self) { group in
            for photo in photos {
                group.addTask {
                    try await repo.delete(url: photo.url)
                }
            }
            try await group.waitForAll()
        }
    }
}
