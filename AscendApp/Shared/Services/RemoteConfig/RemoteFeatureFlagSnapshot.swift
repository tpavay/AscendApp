import Foundation

/// An immutable resolution of every ``RemoteFeatureFlag``, plus where each value came from.
///
/// This type owns the fetch-failure posture and is deliberately free of Firebase: given the set of
/// values the backend actually supplied, it decides what the app believes. That makes the posture
/// unit-testable without a network or a live project.
struct RemoteFeatureFlagSnapshot: Sendable, Equatable {
    /// Where a resolved value came from.
    enum Source: String, Sendable {
        /// The Remote Config backend supplied this value for this device.
        case remote
        /// The backend has never successfully answered for this key, so the compiled-in fallback
        /// stands.
        case shippedDefault
    }

    struct Resolution: Sendable, Equatable {
        let isEnabled: Bool
        let source: Source
    }

    private let resolutions: [RemoteFeatureFlag: Resolution]

    private init(resolutions: [RemoteFeatureFlag: Resolution]) {
        self.resolutions = resolutions
    }

    /// The state the app boots into, before any fetch has been attempted, and the state it stays in
    /// if a fetch never succeeds.
    static let shippedDefaults = RemoteFeatureFlagSnapshot(
        resolutions: Dictionary(
            uniqueKeysWithValues: RemoteFeatureFlag.allCases.map { flag in
                (flag, Resolution(isEnabled: flag.shippedDefault, source: .shippedDefault))
            }
        )
    )

    /// Resolves a snapshot from the values the Remote Config backend supplied.
    ///
    /// `remoteValues` must contain **only** server-sourced values. A key the server did not answer
    /// - because it is absent from the template, because the fetch failed, or because the value did
    /// not parse as a boolean - is left out, and that flag falls back to its ``shippedDefault``.
    /// Keys the app does not recognise are ignored, so the backend can carry parameters for other
    /// app versions without disturbing this one.
    static func resolving(remoteValues: [String: Bool]) -> RemoteFeatureFlagSnapshot {
        RemoteFeatureFlagSnapshot(
            resolutions: Dictionary(
                uniqueKeysWithValues: RemoteFeatureFlag.allCases.map { flag in
                    guard let remoteValue = remoteValues[flag.key] else {
                        return (flag, Resolution(isEnabled: flag.shippedDefault, source: .shippedDefault))
                    }
                    return (flag, Resolution(isEnabled: remoteValue, source: .remote))
                }
            )
        )
    }

    func isEnabled(_ flag: RemoteFeatureFlag) -> Bool {
        resolution(for: flag).isEnabled
    }

    func source(of flag: RemoteFeatureFlag) -> Source {
        resolution(for: flag).source
    }

    /// The flags an operator has actively switched off, for diagnostics. Empty on the happy path,
    /// so a non-empty value is always worth logging.
    var disabledFlagKeys: [String] {
        RemoteFeatureFlag.allCases
            .filter { isEnabled($0) == false }
            .map(\.key)
            .sorted()
    }

    private func resolution(for flag: RemoteFeatureFlag) -> Resolution {
        // `resolutions` is built from `allCases` on every path, so the fallback is unreachable; it
        // exists so a lookup can never be the reason a write path stops working.
        resolutions[flag] ?? Resolution(isEnabled: flag.shippedDefault, source: .shippedDefault)
    }
}
