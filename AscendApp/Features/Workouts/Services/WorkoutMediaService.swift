//
//  WorkoutMediaService.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation
import SwiftData

@MainActor
final class WorkoutMediaService {
    static let shared = WorkoutMediaService()

    private let photoService: PhotoService
    private let pendingUploadManager: any PendingUploadManaging

    init(
        photoService: PhotoService = PhotoService(),
        pendingUploadManager: any PendingUploadManaging = MediaUploadManager.shared
    ) {
        self.photoService = photoService
        self.pendingUploadManager = pendingUploadManager
    }

    func deleteWorkout(_ workout: Workout, modelContext: ModelContext) async throws {
        await pendingUploadManager.cancelUploads(for: workout.id, modelContext: modelContext)

        if !workout.photos.isEmpty {
            try await photoService.deletePhotos(workout.photos)
        }

        modelContext.delete(workout)
        try modelContext.save()
    }

    func deleteWorkouts(_ workouts: [Workout], modelContext: ModelContext) async throws {
        for workout in workouts {
            await pendingUploadManager.cancelUploads(for: workout.id, modelContext: modelContext)
        }

        let allPhotos = workouts.flatMap(\.photos)
        if !allPhotos.isEmpty {
            try await photoService.deletePhotos(allPhotos)
        }

        for workout in workouts {
            modelContext.delete(workout)
        }
        try modelContext.save()
    }

    func removePhoto(
        _ photo: Photo,
        from workout: Workout,
        modelContext: ModelContext
    ) async throws {
        let originalPhotos = workout.photos
        let originalHighlightedPhotoId = workout.highlightedPhotoId

        workout.photos.removeAll { $0.id == photo.id }
        if workout.highlightedPhotoId == photo.id {
            workout.highlightedPhotoId = workout.photos.first?.id
        }

        try modelContext.save()

        do {
            try await photoService.deletePhotos([photo])
        } catch {
            rollbackPhotos(
                for: workout,
                photos: originalPhotos,
                highlightedPhotoId: originalHighlightedPhotoId,
                modelContext: modelContext
            )
            throw error
        }
    }

    func persistPhotoSelection(
        for workout: Workout,
        photos: [Photo],
        highlightedPhotoId: UUID?,
        photosToDelete: [Photo],
        modelContext: ModelContext
    ) async throws {
        let originalPhotos = workout.photos
        let originalHighlightedPhotoId = workout.highlightedPhotoId

        workout.photos = photos
        workout.highlightedPhotoId = highlightedPhotoId ?? photos.first?.id

        try modelContext.save()

        guard !photosToDelete.isEmpty else { return }

        do {
            try await photoService.deletePhotos(photosToDelete)
        } catch {
            rollbackPhotos(
                for: workout,
                photos: originalPhotos,
                highlightedPhotoId: originalHighlightedPhotoId,
                modelContext: modelContext
            )
            throw error
        }
    }

    private func rollbackPhotos(
        for workout: Workout,
        photos: [Photo],
        highlightedPhotoId: UUID?,
        modelContext: ModelContext
    ) {
        workout.photos = photos
        workout.highlightedPhotoId = highlightedPhotoId

        do {
            try modelContext.save()
        } catch {
            print("Workout media rollback failed: \(error)")
        }
    }
}
