import Foundation

struct TelemetryBuildMetadata: Equatable, Sendable {
    static let current = TelemetryBuildMetadata()

    let appEnvironment: String
    let buildConfig: String
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String

    var properties: [String: String] {
        [
            "app_environment": appEnvironment,
            "build_config": buildConfig,
            "app_version": appVersion,
            "build_number": buildNumber
        ]
    }

    var envelope: TelemetryEnvelope? {
        try? TelemetryEnvelope(validating: self)
    }

    var releaseName: String {
        "\(bundleIdentifier)@\(appVersion)+\(buildNumber)"
    }

    init(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "AscendApp"
    ) {
        #if DEBUG
        appEnvironment = "dev"
        buildConfig = "debug"
        #elseif STAGING
        appEnvironment = "staging"
        buildConfig = "staging"
        #else
        appEnvironment = "production"
        buildConfig = "release"
        #endif

        appVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? ""
        buildNumber = infoDictionary["CFBundleVersion"] as? String ?? ""
        self.bundleIdentifier = bundleIdentifier
    }

    init(
        appEnvironment: String,
        buildConfig: String,
        appVersion: String,
        buildNumber: String,
        bundleIdentifier: String
    ) {
        self.appEnvironment = appEnvironment
        self.buildConfig = buildConfig
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
    }
}
