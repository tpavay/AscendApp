//
//  WorkoutService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/21/25.
//

import Foundation
import PhotosUI
import SwiftUI
import SwiftData

final class WorkoutService {
    private let photoService: PhotoService

    init(photoService: PhotoService = PhotoService()) {
        self.photoService = photoService
    }

    // Match the VM boundary on the main actor
    @MainActor
    func createWorkout(from request: CreateWorkoutRequest,
                       with photos: [PhotosPickerItem]) async throws -> Workout {

        // SAFE: this is an actor hop (MainActor -> PhotoService)
        let uploadedPhotos = try await photoService.uploadPhotos(photos)

        // If you read UIKit values, you’re already on the main actor here.
        let model = UIDevice.current.model

        return Workout(
            name: request.name,
            date: request.date,
            duration: request.duration,
            steps: request.steps,
            floors: request.floors,
            notes: request.notes,
            avgHeartRate: request.avgHeartRate,
            maxHeartRate: request.maxHeartRate,
            caloriesBurned: request.caloriesBurned,
            effortRating: request.effortRating,
            source: .manual,
            deviceModel: model,
            photos: uploadedPhotos
        )
    }
}


// Request object to encapsulate workout creation data
struct CreateWorkoutRequest {
    let name: String
    let date: Date
    let duration: TimeInterval
    let steps: Int?
    let floors: Int?
    let notes: String
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let caloriesBurned: Int?
    let effortRating: Double?
}

enum WorkoutServiceError: LocalizedError {
    case photoUploadFailed(String)
    case invalidWorkoutData

    var errorDescription: String? {
        switch self {
        case .photoUploadFailed(let error):
            return "Failed to upload photos: \(error)"
        case .invalidWorkoutData:
            return "Invalid workout data provided"
        }
    }
}
