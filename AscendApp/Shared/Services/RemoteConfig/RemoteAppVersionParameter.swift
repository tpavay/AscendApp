import Foundation

/// Remote Config strings that control whether this installed app version may continue.
///
/// These are deliberately separate from ``RemoteFeatureFlag``. A version threshold is a string
/// policy value, not a Boolean data-path kill switch, and it must never inherit the kill-switch
/// persistence or fallback behavior.
enum RemoteAppVersionParameter: String, CaseIterable, Sendable {
    case minimumSupported = "minimum_supported_app_version"
    case recommended = "recommended_app_version"

    var key: String { rawValue }
}
