//
//  ConsoleScanResult.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import Foundation

/// Result from scanning a stair stepper console via the Cloud Function
struct ConsoleScanResult: Codable {
    let stepsClimbed: Int?
    let floorsClimbed: Double?
    let stepsPerMinute: Double?
    let machineLevel: Double?
    let calories: Double?
    let heartRateBpm: Int?
    let elapsedTimeSeconds: Int?
    let notes: String?

    /// Whether we found any of the primary workout metrics
    var hasValidData: Bool {
        stepsClimbed != nil || floorsClimbed != nil || elapsedTimeSeconds != nil
    }

    /// Whether we found the most important metrics (steps/floors AND time)
    var hasPrimaryMetrics: Bool {
        (stepsClimbed != nil || floorsClimbed != nil) && elapsedTimeSeconds != nil
    }

    // Map snake_case JSON keys from the API to camelCase Swift properties
    enum CodingKeys: String, CodingKey {
        case stepsClimbed = "steps_climbed"
        case floorsClimbed = "floors_climbed"
        case stepsPerMinute = "steps_per_minute"
        case machineLevel = "machine_level"
        case calories
        case heartRateBpm = "heart_rate_bpm"
        case elapsedTimeSeconds = "elapsed_time_seconds"
        case notes
    }

    /// Create a new result with updated values (for edited fields)
    init(
        stepsClimbed: Int? = nil,
        floorsClimbed: Double? = nil,
        stepsPerMinute: Double? = nil,
        machineLevel: Double? = nil,
        calories: Double? = nil,
        heartRateBpm: Int? = nil,
        elapsedTimeSeconds: Int? = nil,
        notes: String? = nil
    ) {
        self.stepsClimbed = stepsClimbed
        self.floorsClimbed = floorsClimbed
        self.stepsPerMinute = stepsPerMinute
        self.machineLevel = machineLevel
        self.calories = calories
        self.heartRateBpm = heartRateBpm
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.notes = notes
    }
}

/// Error types for console scanning
enum ConsoleScanError: LocalizedError {
    case rateLimitExceeded
    case notAuthenticated
    case parseFailure
    case serverError
    case networkError
    case featureDisabled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded:
            return "Daily scan limit reached (5 per day)"
        case .notAuthenticated:
            return "Please sign in to use this feature"
        case .parseFailure:
            return "Unable to interpret console image. Try a clearer photo."
        case .serverError:
            return "Server error while reading console. Try again in a minute."
        case .networkError:
            return "No internet connection"
        case .featureDisabled:
            return "Console scanning is temporarily disabled"
        case .unknown(let message):
            return message
        }
    }

    /// Initialize from HTTP status code and error message
    init(statusCode: Int, message: String) {
        switch statusCode {
        case 401:
            self = .notAuthenticated
        case 429:
            self = .rateLimitExceeded
        case 502:
            self = .parseFailure
        case 503:
            self = .featureDisabled
        case 500:
            self = .serverError
        default:
            self = .unknown(message)
        }
    }
}
