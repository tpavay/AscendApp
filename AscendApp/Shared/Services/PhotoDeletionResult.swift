//
//  PhotoDeletionResult.swift
//  AscendApp
//

import Foundation

/// Represents the result of a photo deletion operation
struct PhotoDeletionResult: Sendable {
    let successfulDeletions: [Photo]
    let failedDeletions: [(photo: Photo, error: any Error)]

    var allSucceeded: Bool {
        failedDeletions.isEmpty
    }

    var failedCount: Int {
        failedDeletions.count
    }
}

/// Configuration for retry behavior
struct PhotoDeletionConfig: Sendable {
    let maxRetries: Int
    let initialDelaySeconds: Double
    let backoffMultiplier: Double
    let timeoutSeconds: Double

    static let `default` = PhotoDeletionConfig(
        maxRetries: 3,
        initialDelaySeconds: 1.0,
        backoffMultiplier: 2.0,
        timeoutSeconds: 15.0
    )
}

/// Errors specific to photo deletion operations
enum PhotoDeletionError: LocalizedError {
    case timeout(url: URL)
    case allRetriesExhausted(url: URL, lastError: any Error)
    case partialFailure(result: PhotoDeletionResult)

    var errorDescription: String? {
        switch self {
        case .timeout(let url):
            return "Photo deletion timed out for \(url.lastPathComponent)"
        case .allRetriesExhausted(let url, let lastError):
            return "Failed to delete \(url.lastPathComponent) after retries: \(lastError.localizedDescription)"
        case .partialFailure(let result):
            return "Failed to delete \(result.failedCount) photo(s) from cloud storage"
        }
    }
}
