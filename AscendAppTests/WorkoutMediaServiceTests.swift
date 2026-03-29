//
//  WorkoutMediaServiceTests.swift
//  AscendAppTests
//
//  Created by Codex on 3/29/26.
//

import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct WorkoutMediaServiceTests {
    @Test
    func deleteWorkoutRemovesWorkoutAfterScopedMediaDeletionSucceeds() async throws {
        let container = try MediaLifecycleTestSupport.makeModelContainer()
        let modelContext = ModelContext(container)
        let photo = Photo(
            url: URL(string: "https://example.com/workout-photo.jpg")!,
            storagePath: "users/test-user/photos/workout-photo.jpg"
        )
        let workout = Workout(
            name: "Leg Day",
            duration: 1_800,
            steps: 2_000,
            floors: 125,
            photos: [photo]
        )
        modelContext.insert(workout)
        try modelContext.save()

        let repository = MockPhotoRepository()
        let pendingUploads = MockPendingUploadManager()
        let service = WorkoutMediaService(
            photoService: PhotoService(repo: repository, deletionConfig: .test),
            pendingUploadManager: pendingUploads
        )

        try await service.deleteWorkout(workout, modelContext: modelContext)

        let remainingWorkouts = try modelContext.fetch(FetchDescriptor<Workout>())
        #expect(remainingWorkouts.isEmpty)
        #expect(pendingUploads.cancelledWorkoutIds == [workout.id])

        let deletedPaths = await repository.recordedDeletedPaths()
        #expect(deletedPaths == ["users/test-user/photos/workout-photo.jpg"])
    }

    @Test
    func deleteWorkoutLeavesWorkoutIntactWhenCloudDeletionFails() async throws {
        let container = try MediaLifecycleTestSupport.makeModelContainer()
        let modelContext = ModelContext(container)
        let photo = Photo(
            url: URL(string: "https://example.com/workout-photo.jpg")!,
            storagePath: "users/test-user/photos/workout-photo.jpg"
        )
        let workout = Workout(
            name: "Leg Day",
            duration: 1_800,
            steps: 2_000,
            floors: 125,
            photos: [photo]
        )
        modelContext.insert(workout)
        try modelContext.save()

        let repository = MockPhotoRepository(deleteBehavior: .fail(.deleteFailed))
        let pendingUploads = MockPendingUploadManager()
        let service = WorkoutMediaService(
            photoService: PhotoService(repo: repository, deletionConfig: .test),
            pendingUploadManager: pendingUploads
        )

        do {
            try await service.deleteWorkout(workout, modelContext: modelContext)
            Issue.record("Expected workout deletion to fail when media cleanup fails.")
        } catch {
            let remainingWorkouts = try modelContext.fetch(FetchDescriptor<Workout>())
            #expect(remainingWorkouts.count == 1)
            #expect(remainingWorkouts.first?.id == workout.id)
            #expect(pendingUploads.cancelledWorkoutIds == [workout.id])

            let deletedPaths = await repository.recordedDeletedPaths()
            #expect(deletedPaths == ["users/test-user/photos/workout-photo.jpg"])
        }
    }

    @Test
    func removePhotoRollsBackLocalMutationWhenCloudDeletionFails() async throws {
        let container = try MediaLifecycleTestSupport.makeModelContainer()
        let modelContext = ModelContext(container)
        let firstPhoto = Photo(
            url: URL(string: "https://example.com/a.jpg")!,
            storagePath: "users/test-user/photos/a.jpg"
        )
        let secondPhoto = Photo(
            url: URL(string: "https://example.com/b.jpg")!,
            storagePath: "users/test-user/photos/b.jpg"
        )
        let workout = Workout(
            name: "Intervals",
            duration: 1_500,
            steps: 1_500,
            floors: 90,
            photos: [firstPhoto, secondPhoto],
            highlightedPhotoId: secondPhoto.id
        )
        modelContext.insert(workout)
        try modelContext.save()

        let repository = MockPhotoRepository(deleteBehavior: .fail(.deleteFailed))
        let service = WorkoutMediaService(
            photoService: PhotoService(repo: repository, deletionConfig: .test),
            pendingUploadManager: MockPendingUploadManager()
        )

        do {
            try await service.removePhoto(secondPhoto, from: workout, modelContext: modelContext)
            Issue.record("Expected photo removal to fail when cloud deletion fails.")
        } catch {
            #expect(workout.photos.map(\.id) == [firstPhoto.id, secondPhoto.id])
            #expect(workout.highlightedPhotoId == secondPhoto.id)

            let deletedPaths = await repository.recordedDeletedPaths()
            #expect(deletedPaths == ["users/test-user/photos/b.jpg"])
        }
    }

    @Test
    func deletePhotosTreatsMissingStorageObjectsAsSuccessfulCleanup() async throws {
        let repository = MockPhotoRepository(deleteBehavior: .objectNotFound)
        let service = PhotoService(repo: repository, deletionConfig: .test)
        let photo = Photo(
            url: URL(string: "https://example.com/missing.jpg")!,
            storagePath: "users/test-user/photos/missing.jpg"
        )

        try await service.deletePhotos([photo])

        let deletedPaths = await repository.recordedDeletedPaths()
        #expect(deletedPaths == ["users/test-user/photos/missing.jpg"])
    }
}
