import Foundation

/// The home-screen icons a climber can pick. The build's primary icon is the seasonal one
/// (`AppIcon`); the everyday lime A ships beside it as an alternate (`AppIconClassic`), so a
/// climber who wants it back never waits for a release. When the season ends, the next release
/// makes the lime A primary again and drops the seasonal art (`docs/seasonal-unlocks.md`).
enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case seasonal
    case classic

    var id: String { rawValue }

    /// The name iOS knows the icon by, nil for the primary.
    var alternateIconName: String? {
        switch self {
        case .seasonal: nil
        case .classic: "AppIconClassic"
        }
    }

    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .seasonal
    }

    var title: String {
        switch self {
        case .seasonal: "Halloween"
        case .classic: "Classic"
        }
    }

    var subtitle: String {
        switch self {
        case .seasonal: "The jack-o'-lantern A, for October."
        case .classic: "The lime A."
        }
    }

    /// A picture of the icon for the picker; an app icon set cannot be drawn by name.
    var previewImageName: String {
        switch self {
        case .seasonal: "AppIconPreviewHalloween"
        case .classic: "AppIconPreviewClassic"
        }
    }
}
