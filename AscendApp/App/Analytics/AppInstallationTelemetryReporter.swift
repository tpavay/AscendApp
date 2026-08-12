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

    /// A suite of its own, deliberately outside the app's own persistent domain: account deletion
    /// clears that domain wholesale (`AppAccountDeletionLocalCleanup.clearUserDefaults`), and a
    /// boundary that a sign-out or a deletion can clear would let one installation report a second
    /// first open. The sentinel is scoped to the installation, not to the account.
    static func installationDefaults(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "AscendApp"
    ) -> UserDefaults {
        UserDefaults(suiteName: "\(bundleIdentifier).installation") ?? .standard
    }
}
