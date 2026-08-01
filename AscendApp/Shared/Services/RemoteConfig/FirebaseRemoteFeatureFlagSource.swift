import FirebaseRemoteConfig
import Foundation

/// The `FirebaseRemoteConfig` adapter behind ``RemoteFeatureFlagService``.
///
/// Two deliberate choices live here:
///
/// - **No `setDefaults`.** The compiled-in fallbacks stay in ``RemoteFeatureFlag/shippedDefault``
///   alone. Handing them to the SDK as well would make `RemoteConfigValue.source` report `.default`
///   for an unfetched key, and the app would lose the ability to tell "the server said on" from
///   "nobody has ever answered". One home for defaults, no drift, and the distinction survives.
/// - **A real-time listener, not a poll.** `addOnConfigUpdateListener` delivers a publish within
///   seconds and bypasses `minimumFetchInterval`, so the periodic fetch is only a backstop for a
///   dropped connection. It is also the cheap shape under usage-based pricing: holding the
///   connection open is not billed, only the download that follows an invalidation.
final class FirebaseRemoteFeatureFlagSource: RemoteFeatureFlagSource, @unchecked Sendable {
    /// Backstop fetch cadence. Real-time updates carry the urgency, so this only has to be short
    /// enough that a device whose connection dropped picks a kill switch up within the hour.
    /// Development and staging fetch on demand so a flag flip is visible immediately during QA.
    #if DEBUG || STAGING
    static let minimumFetchIntervalSeconds: TimeInterval = 0
    #else
    static let minimumFetchIntervalSeconds: TimeInterval = 3600
    #endif

    private let remoteConfig: RemoteConfig
    private let diagnostics: AppDiagnosticsRecorder
    private let registrationLock = NSLock()
    private var registration: ConfigUpdateListenerRegistration?

    init(
        remoteConfig: RemoteConfig = RemoteConfig.remoteConfig(),
        diagnostics: AppDiagnosticsRecorder = .shared
    ) {
        self.remoteConfig = remoteConfig
        self.diagnostics = diagnostics

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = Self.minimumFetchIntervalSeconds
        remoteConfig.configSettings = settings
    }

    deinit {
        registration?.remove()
    }

    func fetchAndActivate() async throws -> [String: Bool] {
        let status = try await remoteConfig.fetchAndActivate()
        switch status {
        case .successFetchedFromRemote, .successUsingPreFetchedData:
            return remoteSourcedValues()
        case .error:
            throw RemoteFeatureFlagSourceError.fetchFailed
        @unknown default:
            throw RemoteFeatureFlagSourceError.fetchFailed
        }
    }

    func startListening(onUpdate: @escaping @Sendable ([String: Bool]) -> Void) {
        let newRegistration = remoteConfig.addOnConfigUpdateListener { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.diagnostics.record(
                    "remote_config_listener_failed",
                    level: .warning,
                    details: ["error_type": String(describing: type(of: error))]
                )
                return
            }

            self.remoteConfig.activate { _, activationError in
                guard activationError == nil else { return }
                onUpdate(self.remoteSourcedValues())
            }
        }

        // Replacing rather than stacking: a second registration would double every callback and
        // leak the first connection for the life of the process.
        registrationLock.lock()
        let previousRegistration = registration
        registration = newRegistration
        registrationLock.unlock()
        previousRegistration?.remove()
    }

    func stopListening() {
        registrationLock.lock()
        let currentRegistration = registration
        registration = nil
        registrationLock.unlock()
        currentRegistration?.remove()
    }

    /// Reads every known flag key, keeping only values the backend actually supplied and that parse
    /// as booleans. A key the template does not carry, or carries as something other than a
    /// boolean, is left out so the flag falls back to its shipped default.
    private func remoteSourcedValues() -> [String: Bool] {
        var values: [String: Bool] = [:]

        for flag in RemoteFeatureFlag.allCases {
            let configValue = remoteConfig.configValue(forKey: flag.key)
            guard configValue.source == .remote else { continue }

            guard let parsed = RemoteFeatureFlagBooleanParser.parse(configValue.stringValue) else {
                diagnostics.record(
                    "remote_config_value_unparseable",
                    level: .error,
                    details: ["flag": flag.key]
                )
                continue
            }

            values[flag.key] = parsed
        }

        return values
    }
}

enum RemoteFeatureFlagSourceError: Error, Equatable {
    case fetchFailed
}
