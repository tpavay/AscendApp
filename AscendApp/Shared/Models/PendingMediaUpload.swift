//
//  PendingMediaUpload.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/11/26.
//

import Foundation
import SwiftData

/// Status of a pending media upload
enum PendingUploadStatus: String, Codable {
    case pending
    case uploading
    case failed
}

/// Tracks media files waiting to be uploaded to Firebase Storage.
/// When upload succeeds, the record is deleted and the Photo is added to Workout.photos.
@Model
final class PendingMediaUpload {
    var id: UUID
    var workoutId: UUID
    var localFileName: String    // Filename in Documents/pending_uploads/
    var mediaType: String        // "photo" or "video" (matches MediaType.rawValue)
    var duration: TimeInterval?  // For videos only
    var status: String           // PendingUploadStatus.rawValue
    var retryCount: Int
    var lastError: String?
    var createdAt: Date
    var orderIndex: Int          // Original position in selection (for ordering)
    var isHighlighted: Bool      // Whether this should become highlightedPhotoId

    init(
        workoutId: UUID,
        localFileName: String,
        mediaType: String,
        duration: TimeInterval? = nil,
        orderIndex: Int,
        isHighlighted: Bool = false
    ) {
        self.id = UUID()
        self.workoutId = workoutId
        self.localFileName = localFileName
        self.mediaType = mediaType
        self.duration = duration
        self.status = PendingUploadStatus.pending.rawValue
        self.retryCount = 0
        self.lastError = nil
        self.createdAt = Date()
        self.orderIndex = orderIndex
        self.isHighlighted = isHighlighted
    }

    // MARK: - Convenience Properties

    var uploadStatus: PendingUploadStatus {
        get { PendingUploadStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    var isVideo: Bool {
        mediaType == MediaType.video.rawValue
    }
}
