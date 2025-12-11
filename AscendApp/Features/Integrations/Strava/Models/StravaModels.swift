//
//  StravaModels.swift
//  AscendApp
//
//  Created by Claude Code on 12/9/24.
//

import Foundation
import SwiftData

// MARK: - Sync Metadata

/// Metadata stored in Workout.stravaSyncData after syncing to Strava
struct StravaSyncMetadata: Codable {
    let stravaActivityId: Int
    let syncedAt: Date

    init(stravaActivityId: Int, syncedAt: Date = Date()) {
        self.stravaActivityId = stravaActivityId
        self.syncedAt = syncedAt
    }
}

// MARK: - Cloud Function Responses

/// Response from stravaCreateOAuthState Cloud Function
struct CreateOAuthStateResponse: Codable {
    let stateId: String
    let clientId: String
}

/// Response from stravaCreateActivity Cloud Function
struct CreateActivityResponse: Codable {
    let success: Bool
    let stravaActivityId: Int?
    let alreadyExists: Bool?
    let message: String?
}

/// Response from stravaDisconnect Cloud Function
struct DisconnectResponse: Codable {
    let success: Bool
}

// MARK: - Workout Request Payload

/// Payload sent to stravaCreateActivity Cloud Function
struct StravaWorkoutPayload: Encodable {
    let workoutId: String
    let name: String
    let date: String  // ISO 8601
    let duration: Int  // seconds
    let floors: Int
    let steps: Int
    let notes: String?
    let tcxContent: String  // Base64-encoded TCX file content
    let primaryMetric: String  // "steps" or "floors"
    let avgSPM: Int  // Average steps per minute

    init(workout: Workout, primaryMetric: WorkoutMetric, stepHeightMeters: Double = 0.2032) {
        self.workoutId = workout.id.uuidString
        self.name = workout.name
        self.date = ISO8601DateFormatter().string(from: workout.date)
        self.duration = Int(workout.duration)
        self.floors = workout.floors
        self.steps = workout.steps
        self.notes = workout.notes.isEmpty ? nil : workout.notes
        self.primaryMetric = primaryMetric.rawValue

        // Calculate average steps per minute
        let minutes = workout.duration / 60.0
        self.avgSPM = minutes > 0 ? Int((Double(workout.steps) / minutes).rounded()) : 0

        // Generate TCX file and encode as base64
        let tcxString = TCXGenerator.generate(from: workout, stepHeightMeters: stepHeightMeters)
        self.tcxContent = Data(tcxString.utf8).base64EncodedString()
    }
}

// MARK: - Strava Errors

enum StravaError: LocalizedError {
    case notConnected
    case notConfigured
    case authenticationFailed(String)
    case activityCreationFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Strava"
        case .notConfigured:
            return "Connection error. Please try again."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .activityCreationFailed(let message):
            return "Failed to create activity: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
