//
//  HevyModels.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import Foundation

// MARK: - Exercise History Response

struct HevyExerciseHistoryResponse: Codable {
    let exercise_history: [HevyExerciseHistory]
    let page: Int?
    let page_count: Int?
}

struct HevyExerciseHistory: Codable {
    let workout_id: String
    let workout_title: String
    let workout_start_time: String
    let workout_end_time: String?
    let exercise_template_id: String?
    let weight_kg: Double?
    let reps: Int?
    let distance_meters: Double?
    let duration_seconds: Int?
    let rpe: Double?
    let custom_metric: Double?  // Steps or floors count
    let set_type: String?

    /// Parses workout_start_time to Date
    var startDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: workout_start_time) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: workout_start_time)
    }

    /// Parses workout_end_time to Date
    var endDate: Date? {
        guard let endTime = workout_end_time else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: endTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: endTime)
    }

    /// Steps/floors count as integer
    var metricValue: Int {
        Int(custom_metric ?? 0)
    }

    /// Duration in TimeInterval (seconds)
    var duration: TimeInterval {
        TimeInterval(duration_seconds ?? 0)
    }
}

// MARK: - Exercise Templates Response

struct HevyExerciseTemplatesResponse: Codable {
    let exercise_templates: [HevyExerciseTemplate]
    let page: Int?
    let page_count: Int?
}

struct HevyExerciseTemplate: Codable {
    let id: String
    let title: String
    let type: String?
    let primary_muscle_group: String?
    let secondary_muscle_groups: [String]?
    let is_custom: Bool?
}

// MARK: - Hevy Errors

enum HevyError: LocalizedError {
    case invalidApiKey
    case rateLimited(retryAfter: Int?)
    case networkError(Error)
    case noStairmasterTemplateFound
    case decodingError(Error)
    case unknownError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Invalid API key. Please check your Hevy API key and try again."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Hevy is busy. Please try again in \(seconds) seconds."
            }
            return "Hevy is busy. Please try again in a moment."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noStairmasterTemplateFound:
            return "No stairmaster exercise found in your Hevy account. Please log a \"Stair Machine\" exercise in Hevy first."
        case .decodingError(let error):
            return "Failed to parse Hevy response: \(error.localizedDescription)"
        case .unknownError(let statusCode):
            return "Hevy API error (status \(statusCode))"
        }
    }
}

// MARK: - Hevy Sync State

/// Stores sync metadata in UserDefaults
struct HevySyncState {
    private static let lastSyncKey = "lastHevySyncAt"
    private static let templateIdKey = "hevyTemplateId"
    private static let templateTypeKey = "hevyTemplateType" // "steps" or "floors"

    static var lastSyncAt: Date? {
        get {
            UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastSyncKey)
        }
    }

    static var templateId: String? {
        get {
            UserDefaults.standard.string(forKey: templateIdKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: templateIdKey)
        }
    }

    static var templateType: String? {
        get {
            UserDefaults.standard.string(forKey: templateTypeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: templateTypeKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        UserDefaults.standard.removeObject(forKey: templateIdKey)
        UserDefaults.standard.removeObject(forKey: templateTypeKey)
    }
}
