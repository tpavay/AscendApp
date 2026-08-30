import Foundation

/// Whether this process is running on a simulator rather than on somebody's phone.
///
/// `TelemetryBuildMetadata` cannot answer this. A Release binary compiled for the simulator
/// SDK reports `production` / `release` exactly like a customer's build, which is how 34
/// simulator identities and 167 events reached the production Mixpanel project inside one
/// 4.7-hour afternoon - 21 of the 34 users on the onboarding funnel's last step. Nothing in
/// the event payload could tell them apart afterwards; `$model == "arm64"` was the only tell.
struct TelemetryRuntimeEnvironment: Equatable, Sendable {
    static let current = TelemetryRuntimeEnvironment()

    let isSimulator: Bool

    init(processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        // Two independent answers, because either one alone can be wrong in the direction that
        // costs production data: the compile-time flag is missing from a device-SDK binary that
        // simulator tooling launched anyway, and the process variables are absent from a build
        // launched outside Xcode's simulator harness.
        isSimulator = Self.isCompiledForSimulator
            || Self.simulatorProcessKeys.contains { processEnvironment[$0] != nil }
    }

    init(isSimulator: Bool) {
        self.isSimulator = isSimulator
    }

    static var isCompiledForSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Stamped into every process a simulator runtime hosts.
    private static let simulatorProcessKeys = [
        "SIMULATOR_UDID",
        "SIMULATOR_DEVICE_NAME",
        "SIMULATOR_MODEL_IDENTIFIER",
        "SIMULATOR_ROOT"
    ]
}
