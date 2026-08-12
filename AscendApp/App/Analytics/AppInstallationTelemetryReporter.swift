import Foundation

@MainActor
final class AppInstallationTelemetryReporter {
    static let shared = AppInstallationTelemetryReporter()

    private static let firstOpenRecordedKey = "telemetry.appFirstOpenRecorded.v1"

    private let telemetry: TelemetryManager
    private let defaults: UserDefaults
    private let buildMetadata: TelemetryBuildMetadata

    init(
        telemetry: TelemetryManager = .shared,
        defaults: UserDefaults = AppInstallationTelemetryReporter.installationDefaults(),
        buildMetadata: TelemetryBuildMetadata = .current
    ) {
        self.telemetry = telemetry
        self.defaults = defaults
        self.buildMetadata = buildMetadata
    }

    func recordFirstOpenIfNeeded() {
        guard defaults.bool(forKey: Self.firstOpenRecordedKey) == false else { return }

        // Persist before handing the event to SDK-backed sinks. A crash or relaunch can never turn
        // the same installation into a second first open, even if the sink is unavailable.
        defaults.set(true, forKey: Self.firstOpenRecordedKey)
        telemetry.track(
            AppLifecycleAnalyticsEvent.firstOpened(
                appVersion: buildMetadata.resolvedAppVersion,
                buildNumber: buildMetadata.resolvedBuildNumber
            )
        )
    }

    static func installationDefaults(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "AscendApp"
    ) -> UserDefaults {
        UserDefaults(suiteName: "\(bundleIdentifier).installation") ?? .standard
    }
}
