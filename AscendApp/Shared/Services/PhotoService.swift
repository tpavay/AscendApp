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
    
    /// Upload photos from SelectedPhotoItems (supports trimmed videos)
    func uploadSelectedPhotos(_ items: [SelectedPhotoItem]) async throws -> [Photo] {
        let repo = self.repo
        return try await withThrowingTaskGroup(of: (Photo?, URL?, URL?).self) { group in
            for item in items {
                group.addTask {
                    if item.isVideo {
                        // Use trimmed video if available, otherwise load from picker
                        if let trimmedURL = item.trimmedVideoURL,
                           let trimmedDuration = item.trimmedDuration {
                            let photo = try await self.uploadVideoFromURL(trimmedURL, duration: trimmedDuration, repo: repo)
                            return (photo, trimmedURL, item.originalVideoURL)
                        } else if let originalURL = item.originalVideoURL {
                            let photo = try await self.uploadVideoFromURL(originalURL, duration: item.duration ?? 0, repo: repo)
                            return (photo, nil, originalURL)
                        } else {
                            let photo = try await self.uploadVideo(item.pickerItem, repo: repo)
                            return (photo, nil, nil)
                        }
                    } else {
                        let photo = try await self.uploadPhoto(item.pickerItem, repo: repo)
                        return (photo, nil, nil)
                    }
                }
            }
            var out: [Photo] = []
            for try await result in group {
                if let photo = result.0 {
                    out.append(photo)
                }
                // Clean up temporary files after successful upload
                if let trimmedURL = result.1 {
                    try? FileManager.default.removeItem(at: trimmedURL)
                }
                if let originalURL = result.2 {
                    try? FileManager.default.removeItem(at: originalURL)
                }
            }
            return out
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
