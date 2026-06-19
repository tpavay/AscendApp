//
//  LocalMediaStorage.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/11/26.
//

import Foundation

/// Handles local file storage for pending media uploads.
/// All disk IO operations run on background threads via Task.detached to avoid UI hitches.
enum LocalMediaStorage {
    static let pendingUploadsDirectory = "pending_uploads"

    // MARK: - Directory Management

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var pendingUploadsURL: URL {
        documentsDirectory.appendingPathComponent(pendingUploadsDirectory)
    }

    private static func createDirectoryIfNeeded() throws {
        let url = pendingUploadsURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - File URL

    /// Get the full URL for a filename in the pending uploads directory.
    /// This is synchronous as it doesn't perform any IO.
    static func fileURL(for filename: String) -> URL {
        pendingUploadsURL.appendingPathComponent(filename)
    }

    // MARK: - Save Operations (async, runs on background thread)

    /// Save photo data to local storage.
    /// - Parameter data: The photo data (typically JPEG)
    /// - Returns: The filename (UUID.jpg)
    static func savePhoto(data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let filename = "\(UUID().uuidString).jpg"
            let url = fileURL(for: filename)
            try createDirectoryIfNeeded()
            try data.write(to: url)
            return filename
        }.value
    }

    /// Save video from an existing URL (e.g., pre-trimmed video).
    /// - Parameter sourceURL: The source video URL
    /// - Returns: The filename (UUID.extension)
    static func saveVideo(from sourceURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let filename = "\(UUID().uuidString).\(sourceURL.pathExtension)"
            let destURL = fileURL(for: filename)
            try createDirectoryIfNeeded()
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return filename
        }.value
    }

    // MARK: - Delete Operations (async, runs on background thread)

    /// Delete a file by filename.
    /// - Parameter filename: The filename to delete
    static func delete(filename: String) async throws {
        try await Task.detached(priority: .utility) {
            let url = fileURL(for: filename)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }.value
    }

    /// Delete a file, ignoring errors. Useful for cleanup where failures are acceptable.
    /// - Parameter filename: The filename to delete
    static func deleteIfExists(filename: String) async {
        try? await delete(filename: filename)
    }

    // MARK: - Cleanup (async, tolerant of errors)

    /// Clean up orphaned files that aren't referenced by any PendingMediaUpload.
    /// Runs in background with low priority. Tolerates individual file delete errors.
    /// - Parameter validFilenames: Set of filenames that should be kept
    static func cleanupOrphanedFiles(validFilenames: Set<String>) async {
        await Task.detached(priority: .background) {
            let directory = pendingUploadsURL

            guard FileManager.default.fileExists(atPath: directory.path),
                  let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                return
            }

            for file in files where !validFilenames.contains(file) {
                do {
                    try FileManager.default.removeItem(at: directory.appendingPathComponent(file))
                    debugLog("[LocalMediaStorage] Deleted orphan file: \(file)")
                } catch {
                    // Log error but don't block - orphan will be cleaned up next time
                    debugLog("[LocalMediaStorage] Failed to delete orphan file \(file): \(error.localizedDescription)")
                }
            }
        }.value
    }

    /// Remove the entire pending uploads directory and all contents.
    static func clearAllPendingUploads() async throws {
        try await Task.detached(priority: .utility) {
            let directory = pendingUploadsURL
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }.value
    }

    // MARK: - Read Operations

    /// Read file data from local storage.
    /// - Parameter filename: The filename to read
    /// - Returns: The file data
    static func readData(filename: String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let url = fileURL(for: filename)
            return try Data(contentsOf: url)
        }.value
    }
}
