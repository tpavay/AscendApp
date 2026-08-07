import Foundation

/// Supplies server-sourced flag values to ``RemoteFeatureFlagService``.
///
/// Implementations return **only** values the backend actually answered with, keyed by Remote
/// Config parameter key. Anything the backend did not supply is simply absent from the dictionary;
/// deciding what to do about that is ``RemoteFeatureFlagSnapshot``'s job, not the source's.
protocol RemoteFeatureFlagSource: Sendable {
    /// Fetches the latest template and activates it. Throws if the fetch fails, so the caller can
    /// tell "the backend said nothing" apart from "the backend said nothing new".
    func fetchAndActivate() async throws -> [String: Bool]

    /// The values already activated on this device, read without touching the network.
    ///
    /// This is what makes a kill switch durable: a fetch throws when the device is offline, so
    /// without reading the persisted activation a cold launch in aeroplane mode would run every
    /// flag on its shipped default while the SDK still held the `false` an operator published.
    func activatedValues() -> [String: Bool]

    /// Reads version strings from the activation produced by the most recent successful fetch.
    ///
    /// The service calls this only after ``fetchAndActivate()`` succeeds. It is intentionally not
    /// part of persisted launch seeding, because a cached threshold or an SDK default must never
    /// block a launch whose fetch has not resolved successfully.
    func appVersionValues() -> [String: String]

    /// Opens a real-time connection and reports every activated update.
    ///
    /// Calling this twice replaces the previous registration rather than stacking a second one.
    func startListening(onUpdate: @escaping @Sendable ([String: Bool]) -> Void)

    /// Closes the real-time connection. Safe to call when not listening.
    func stopListening()
}

/// Parses the string values Remote Config stores into booleans.
///
/// Deliberately strict: an unrecognised value is *not* coerced to `false`, because a malformed
/// template entry silently reading as "off" would disable a data path nobody chose to disable.
/// Unrecognised values are reported as `nil` so the flag falls back to its shipped default and the
/// caller can log the malformed key.
enum RemoteFeatureFlagBooleanParser {
    private static let trueLiterals: Set<String> = ["true", "yes", "y", "t", "1"]
    private static let falseLiterals: Set<String> = ["false", "no", "n", "f", "0"]

    static func parse(_ rawValue: String) -> Bool? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trueLiterals.contains(normalized) { return true }
        if falseLiterals.contains(normalized) { return false }
        return nil
    }
}
