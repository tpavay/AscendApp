import Foundation

enum AppleHealthImportAnalyticsEvent: TelemetryEvent {
    /// A stair workout Ascend read from Health and did not turn into a climb.
    case workoutSkipped(HealthWorkoutSkip)

    var record: TelemetryRecord {
        switch self {
        case .workoutSkipped(let skip):
            var parameters: [String: TelemetryValue] = [
                "reason": .string(skip.reason.rawValue),
                "source_bundle_id": .string(Self.reportedBundleIdentifier(skip.sourceBundleIdentifier)),
                "duration_bucket": .string(Self.durationBucket(skip.duration))
            ]
            if let activityType = skip.activityTypeRawValue {
                parameters["activity_type"] = .int(Int(activityType))
            }
            return TelemetryRecord(name: "apple_health_workout_skipped", parameters: parameters)
        }
    }

    /// The app that wrote the workout, as a value that names an app and never a device.
    ///
    /// An Apple Watch writes under `com.apple.health.<a UUID of that watch>`, which would put one
    /// value per climber's watch into a property meant to hold a handful of app names.
    static func reportedBundleIdentifier(_ identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "unknown" }
        let appleHealth = "com.apple.health"
        return identifier.hasPrefix(appleHealth + ".") ? appleHealth : identifier
    }

    /// How long the workout ran, coarse enough to say "a session" or "a blip" and nothing more.
    static func durationBucket(_ duration: TimeInterval) -> String {
        switch duration {
        case ..<1: "under_1s"
        case ..<60: "under_1m"
        case ..<600: "1_to_10m"
        case ..<1_800: "10_to_30m"
        case ..<3_600: "30_to_60m"
        case ..<7_200: "1_to_2h"
        case ...ClimbPacePolicy.maximumDuration: "2_to_24h"
        default: "over_24h"
        }
    }
}
