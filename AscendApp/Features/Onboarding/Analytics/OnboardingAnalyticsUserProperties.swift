import Foundation

enum OnboardingAnalyticsUserProperties {
    static func setNotificationChoice(_ choice: String, telemetry: TelemetryManager = .shared) {
        set("notifications_choice", choice, telemetry: telemetry)
    }

    static func setEmailOptIn(_ optedIn: Bool, telemetry: TelemetryManager = .shared) {
        set("email_opt_in", optedIn ? "true" : "false", telemetry: telemetry)
    }

    static func setOnboardingCompleted() {
        set("onboarding_complete", "true")
    }

    private static func set(_ name: String, _ value: String, telemetry: TelemetryManager = .shared) {
        telemetry.setUserProperty(name, value: value)
    }
}
