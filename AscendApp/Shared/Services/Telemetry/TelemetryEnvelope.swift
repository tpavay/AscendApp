import Foundation

struct TelemetryEnvelope: Sendable, Hashable, Equatable {
    enum ValidationError: Error, Equatable {
        case inconsistentEnvironment
        case missingAppVersion
        case missingBuildNumber
    }

    let appEnvironment: String
    let buildConfig: String
    let appVersion: String
    let buildNumber: String

    var properties: [String: TelemetryValue] {
        [
            "app_environment": .string(appEnvironment),
            "build_config": .string(buildConfig),
            "app_version": .string(appVersion),
            "build_number": .string(buildNumber)
        ]
    }

    init(validating metadata: TelemetryBuildMetadata) throws {
        let expectedBuildConfig: String? = switch metadata.appEnvironment {
        case "dev": "debug"
        case "staging": "staging"
        case "production": "release"
        default: nil
        }

        guard expectedBuildConfig == metadata.buildConfig else {
            throw ValidationError.inconsistentEnvironment
        }
        guard metadata.appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ValidationError.missingAppVersion
        }
        guard metadata.buildNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ValidationError.missingBuildNumber
        }

        appEnvironment = metadata.appEnvironment
        buildConfig = metadata.buildConfig
        appVersion = metadata.appVersion
        buildNumber = metadata.buildNumber
    }
}
