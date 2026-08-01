//
//  MediaUploadManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/11/26.
//

import Foundation
import SwiftData
import PhotosUI
import FirebaseAuth

/// Status of media uploads for a workout
enum MediaUploadStatus: Equatable {
    case none                                    // No pending uploads
    case uploading(current: Int, total: Int)     // "Uploading 1 of 3..."
    case failed(count: Int)                      // "2 uploads failed"
}

/// Errors that can occur during media upload
enum UploadError: LocalizedError {
    case timeout
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Upload timed out"
        case .notAuthenticated:
            return "You must be signed in to upload media."
        }
    }
}

/// Manages asynchronous media uploads for workouts.
/// - Queues uploads when workouts are saved
/// - Processes uploads in background
/// - Handles retries with exponential backoff
/// - Persists uploads across app restarts
@MainActor
@Observable
final class MediaUploadManager {
    static let shared = MediaUploadManager()

    // MARK: - Observable State

    /// Upload status per workout (for UI observation)
    private(set) var uploadStatuses: [UUID: MediaUploadStatus] = [:]

    // MARK: - Private State

    /// Active upload tasks keyed by PendingMediaUpload.id (for cancellation)
    private var activeUploadTasks: [UUID: Task<Bool, Never>] = [:]

    /// Workouts currently being processed (prevents double-processing)
    private var processingWorkoutIds: Set<UUID> = []

    /// Repository for Firebase uploads
    private let photoRepo: any PhotoRepositoryProtocol

    // MARK: - Configuration

    private let maxRetries = 3
    private let initialDelaySeconds: Double = 1.0
    private let backoffMultiplier: Double = 2.0
    private let uploadTimeoutSeconds: Double = 60.0  // Timeout per upload attempt

    // MARK: - Initialization

    /// Server-controlled off switch for the background queue below.
    private let featureFlags: RemoteFeatureFlagStore

    init(
        photoRepo: any PhotoRepositoryProtocol = FirebasePhotoRepository(),
        featureFlags: RemoteFeatureFlagStore = .shared
    ) {
        self.photoRepo = photoRepo
        self.featureFlags = featureFlags
    }

    // MARK: - Public API

    /// Get the upload status for a specific workout
    func uploadStatus(for workoutId: UUID) -> MediaUploadStatus {
        uploadStatuses[workoutId] ?? .none
    }

    /// Whether the queue may run right now. Read by the UI so a thrown kill switch neither claims
    /// an upload is in progress nor offers a retry that cannot happen.
    var isUploadQueueActive: Bool {
        featureFlags.isEnabled(.workoutMediaUploads)
    }

    /// Pure derivation of what the banner should say, so the rule that a held queue never reports
    /// itself as uploading is testable without a picker item.
    static func resolvedStatus(
        pendingCount: Int,
        failedCount: Int,
        isQueueActive: Bool
    ) -> MediaUploadStatus {
        if failedCount > 0 {
            return .failed(count: failedCount)
        }
        guard isQueueActive, pendingCount > 0 else {
            return .none
        }
        return .uploading(current: 1, total: pendingCount)
    }

    /// Queue new uploads for a workout.
    /// Saves media files locally and creates PendingMediaUpload records.
    /// - Parameters:
    ///   - workoutId: The workout ID to associate uploads with
    ///   - photos: Selected photos/videos to upload
    ///   - highlightedIndex: Index of the highlighted photo (if any)
    ///   - modelContext: SwiftData model context
    func queueUploads(
        for workoutId: UUID,
        photos: [SelectedPhotoItem],
        highlightedIndex: Int?,
        modelContext: ModelContext
    ) async throws {
        guard !photos.isEmpty else { return }

        // Save files locally and create PendingMediaUpload records
        for (index, item) in photos.enumerated() {
            let filename: String
            let mediaType: String
            let duration: TimeInterval?

            if item.isVideo {
                mediaType = MediaType.video.rawValue
                duration = item.duration

                if let videoURL = item.videoURL {
                    // Pre-trimmed video: copy from existing URL
                    filename = try await LocalMediaStorage.saveVideo(from: videoURL)
                } else {
                    // Load via VideoPickerTransferable
                    guard let video = try await item.pickerItem.loadTransferable(type: VideoPickerTransferable.self) else {
                        continue
                    }
                    filename = try await LocalMediaStorage.saveVideo(from: video.url)
                    // Clean up the temp file from VideoPickerTransferable
                    try? FileManager.default.removeItem(at: video.url)
                }
            } else {
                mediaType = MediaType.photo.rawValue
                duration = nil

                guard let data = try await item.pickerItem.loadTransferable(type: Data.self) else {
                    continue
                }
                filename = try await LocalMediaStorage.savePhoto(data: data)
            }

            // Create pending upload record
            let pending = PendingMediaUpload(
                workoutId: workoutId,
                localFileName: filename,
                mediaType: mediaType,
                duration: duration,
                orderIndex: index,
                isHighlighted: index == highlightedIndex
            )
            modelContext.insert(pending)
        }

        try modelContext.save()

        // Update status and start processing
        updateStatus(for: workoutId, modelContext: modelContext)

        // Start upload processing
        await processUploadsForWorkout(workoutId: workoutId, modelContext: modelContext)
    }

    /// Retry all failed uploads for a workout
    func retryFailedUploads(for workoutId: UUID, modelContext: ModelContext) async {
        // Checked before the rows are touched, not just before the upload: a reset to `pending`
        // would be a status change on work the switch says must sit exactly as it is.
        guard mediaUploadsAllowed(path: "MediaUploadManager.retryFailedUploads") else { return }

        // Reset failed uploads to pending
        let descriptor = FetchDescriptor<PendingMediaUpload>(
            predicate: #Predicate { $0.workoutId == workoutId && $0.status == "failed" }
        )

        guard let failedUploads = try? modelContext.fetch(descriptor) else { return }

        for upload in failedUploads {
            upload.uploadStatus = .pending
            upload.retryCount = 0
            upload.lastError = nil
        }

        try? modelContext.save()

        updateStatus(for: workoutId, modelContext: modelContext)
        await processUploadsForWorkout(workoutId: workoutId, modelContext: modelContext)
    }

    /// Process all pending uploads (called on app launch/foreground)
    func processPendingUploads(modelContext: ModelContext) async {
        // Also gated here, above `processUploadsForWorkout`, because the orphaned-file cleanup at
        // the end of this sweep is local deletion the switch is meant to stop as well.
        guard mediaUploadsAllowed(path: "MediaUploadManager.processPendingUploads") else { return }

        let descriptor = FetchDescriptor<PendingMediaUpload>(
            predicate: #Predicate { $0.status == "pending" || $0.status == "uploading" }
        )

        guard let pending = try? modelContext.fetch(descriptor) else { return }

        // Get unique workout IDs
        let workoutIds = Set(pending.map { $0.workoutId })

        // Process each workout's uploads
        for workoutId in workoutIds {
            guard !processingWorkoutIds.contains(workoutId) else { continue }

            updateStatus(for: workoutId, modelContext: modelContext)
            await processUploadsForWorkout(workoutId: workoutId, modelContext: modelContext)
        }

        // Clean up orphaned local files
        let allFilenames = Set(pending.map { $0.localFileName })
        await LocalMediaStorage.cleanupOrphanedFiles(validFilenames: allFilenames)
    }

    /// Cancel all pending uploads for a workout (when workout is deleted)
    func cancelUploads(for workoutId: UUID, modelContext: ModelContext) async {
        // Cancel all active upload tasks for this workout
        let descriptor = FetchDescriptor<PendingMediaUpload>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        if let uploads = try? modelContext.fetch(descriptor) {
            for upload in uploads {
                // Cancel active task
                activeUploadTasks[upload.id]?.cancel()
                activeUploadTasks[upload.id] = nil

                // Delete local file
                await LocalMediaStorage.deleteIfExists(filename: upload.localFileName)

                // Delete record
                modelContext.delete(upload)
            }
        }

        try? modelContext.save()

        // Clear status
        uploadStatuses[workoutId] = nil
        processingWorkoutIds.remove(workoutId)
    }

    // MARK: - Private Methods

    /// Whether the media queue may run. The switch exists for the upload's second half - deleting
    /// the local original once Cloud Storage is believed to have it - so every path that can reach
    /// that deletion asks here.
    private func mediaUploadsAllowed(path: String) -> Bool {
        RemoteFeatureGate.allows(.workoutMediaUploads, path: path, store: featureFlags)
    }

    /// Process uploads for a specific workout
    private func processUploadsForWorkout(workoutId: UUID, modelContext: ModelContext) async {
        // The single choke point every entry point funnels through, so a save-triggered enqueue
        // cannot upload and delete a local original behind a thrown switch. The
        // `PendingMediaUpload` rows are left exactly as they are and drain when the flag returns.
        guard mediaUploadsAllowed(path: "MediaUploadManager.processUploadsForWorkout") else { return }

        guard !processingWorkoutIds.contains(workoutId) else { return }
        processingWorkoutIds.insert(workoutId)

        defer {
            processingWorkoutIds.remove(workoutId)
            updateStatus(for: workoutId, modelContext: modelContext)
        }

        // Fetch pending uploads for this workout
        let descriptor = FetchDescriptor<PendingMediaUpload>(
            predicate: #Predicate { $0.workoutId == workoutId && $0.status == "pending" },
            sortBy: [SortDescriptor(\PendingMediaUpload.orderIndex)]
        )

        guard let pendingUploads = try? modelContext.fetch(descriptor), !pendingUploads.isEmpty else {
            return
        }

        // Fetch the workout
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.id == workoutId }
        )
        guard let workout = try? modelContext.fetch(workoutDescriptor).first else {
            return
        }

        // Process uploads sequentially
        var didUploadAnyMedia = false

        for (currentIndex, upload) in pendingUploads.enumerated() {
            // Update status to show progress
            let total = pendingUploads.count
            uploadStatuses[workoutId] = .uploading(current: currentIndex + 1, total: total)

            // Create task for this upload
            let task = Task<Bool, Never> { [weak self] in
                guard let self else { return false }
                return await self.processUpload(
                    upload,
                    workout: workout,
                    modelContext: modelContext
                )
            }

            activeUploadTasks[upload.id] = task
            let didUploadMedia = await task.value
            activeUploadTasks[upload.id] = nil
            didUploadAnyMedia = didUploadAnyMedia || didUploadMedia

            // Check if cancelled
            if Task.isCancelled { break }
        }

        guard didUploadAnyMedia else { return }
        await queueRemoteSyncForUploadedMedia(
            workoutId: workoutId,
            modelContext: modelContext
        )
    }

    /// Process a single upload with retry logic
    private func processUpload(
        _ upload: PendingMediaUpload,
        workout: Workout,
        modelContext: ModelContext
    ) async -> Bool {
        upload.uploadStatus = .uploading
        try? modelContext.save()

        var lastError: Error?
        var currentDelay = initialDelaySeconds

        for attempt in 0..<maxRetries {
            if Task.isCancelled { return false }

            do {
                // Read local file data
                let data = try await LocalMediaStorage.readData(filename: upload.localFileName)

                // Determine Firebase path
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw UploadError.notAuthenticated
                }

                let fileExtension = upload.isVideo ?
                    (URL(fileURLWithPath: upload.localFileName).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: upload.localFileName).pathExtension) :
                    "jpg"
                let path = upload.isVideo ?
                    "users/\(userId)/videos/\(UUID().uuidString).\(fileExtension)" :
                    "users/\(userId)/photos/\(UUID().uuidString).jpg"

                // Upload to Firebase with timeout
                let remoteURL = try await withThrowingTaskGroup(of: URL.self) { group in
                    group.addTask {
                        try await self.photoRepo.upload(data, filename: path)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(self.uploadTimeoutSeconds))
                        throw UploadError.timeout
                    }

                    // Return first result (either success or timeout)
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }

                // Success! Create Photo and update Workout
                let photo = Photo(
                    url: remoteURL,
                    type: upload.isVideo ? .video : .photo,
                    duration: upload.duration
                )

                // Insert at correct position to maintain order
                let insertIndex = min(upload.orderIndex, workout.photos.count)
                workout.photos.insert(photo, at: insertIndex)

                // Set highlighted photo if this was the highlighted one
                if upload.isHighlighted {
                    workout.highlightedPhotoId = photo.id
                }

                // Delete pending record and local file
                modelContext.delete(upload)
                try? modelContext.save()
                await LocalMediaStorage.deleteIfExists(filename: upload.localFileName)

                return true // Success

            } catch {
                lastError = error
                debugLog("[MediaUploadManager] Upload attempt \(attempt + 1) failed for \(upload.localFileName): \(error.localizedDescription)")

                if Task.isCancelled { return false }

                // Wait before retry (unless last attempt)
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(currentDelay))
                    currentDelay *= backoffMultiplier
                }
            }
        }

        // All retries exhausted - mark as failed
        upload.uploadStatus = .failed
        upload.retryCount = maxRetries
        upload.lastError = lastError?.localizedDescription ?? "Unknown error"
        if let lastError {
            TelemetryManager.shared.recordError(
                lastError,
                context: .storage,
                code: upload.isVideo ? "video_upload_failed" : "photo_upload_failed",
                additionalInfo: ["media_type": upload.mediaType]
            )
            debugLog("[MediaUploadManager] Upload failed after \(maxRetries) attempts for \(upload.localFileName): \(lastError.localizedDescription)")
        } else {
            debugLog("[MediaUploadManager] Upload failed after \(maxRetries) attempts for \(upload.localFileName): Unknown error")
        }
        try? modelContext.save()
        return false
    }

    private func queueRemoteSyncForUploadedMedia(
        workoutId: UUID,
        modelContext: ModelContext
    ) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.id == workoutId
            }
        )

        guard let workout = try? modelContext.fetch(descriptor).first else { return }

        workout.markPendingRemoteUpsert(ownerUserId: currentUserId)

        do {
            try modelContext.save()
        } catch {
            debugLog("[MediaUploadManager] Failed to mark workout \(workoutId) pending for remote sync: \(error.localizedDescription)")
            return
        }

        await WorkoutSyncCoordinator.shared.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: currentUserId
        )
    }

    /// Update the upload status for a workout based on pending uploads
    private func updateStatus(for workoutId: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PendingMediaUpload>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        guard let uploads = try? modelContext.fetch(descriptor) else {
            uploadStatuses[workoutId] = MediaUploadStatus.none
            return
        }

        if uploads.isEmpty {
            uploadStatuses[workoutId] = MediaUploadStatus.none
            return
        }

        let failedCount = uploads.filter { $0.status == PendingUploadStatus.failed.rawValue }.count
        let pendingCount = uploads.filter { $0.status == PendingUploadStatus.pending.rawValue || $0.status == PendingUploadStatus.uploading.rawValue }.count

        uploadStatuses[workoutId] = Self.resolvedStatus(
            pendingCount: pendingCount,
            failedCount: failedCount,
            isQueueActive: isUploadQueueActive
        )
    }
}
