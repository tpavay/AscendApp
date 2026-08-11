/// Code compiled into **both** the iPhone app and the watch app.
///
/// The folder is a `PBXFileSystemSynchronizedRootGroup` listed in the
/// `fileSystemSynchronizedGroups` of both targets, which is the same mechanism
/// that already shares `AscendApp/Features/Climbs/LiveActivity` with the widget
/// extension. Adding a file here compiles it into both binaries; there is no
/// membership list to remember.
///
/// What belongs here: platform-neutral value types the two sides must agree on -
/// the wire payloads, and the descriptions a watch face renders. What does not:
/// anything importing Firebase, SwiftData, Mapbox, or UIKit. None of that
/// compiles for watchOS, and the watch target's compile is the enforcement.
///
/// Deliberately thin today. The wire types arrive with the transport that needs
/// them rather than ahead of it, and the vocabulary a session already owns
/// (`HeadphoneMotionWorkoutTrackingMode`) is not re-declared here - two copies
/// of a contract become two different contracts.
enum AscendWatchShared {
    /// The watch app's bundle identifier is its companion iPhone app's plus this
    /// suffix, in every environment. Both halves reason about the pair: the phone
    /// resolves whether its own watch app is installed, and the watch reports
    /// which companion it was built against.
    ///
    /// This mirrors `WKCompanionAppBundleIdentifier` and the per-configuration
    /// `PRODUCT_BUNDLE_IDENTIFIER` values in the project file. Those are the
    /// authority; this exists so neither side hardcodes the relationship twice.
    static let watchAppBundleIdentifierSuffix = ".watch"

    /// The watch bundle identifier for a given companion iPhone bundle identifier.
    static func watchAppBundleIdentifier(companion: String) -> String {
        companion + watchAppBundleIdentifierSuffix
    }
}
