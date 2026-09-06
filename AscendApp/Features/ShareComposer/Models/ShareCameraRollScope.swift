import Foundation

/// What the Camera Roll tab is currently showing.
///
/// The album browser is a selection rather than a route, because the filter row above it stays put
/// and is how the climber leaves. That also makes it the one selection that is not showing photos,
/// which is what the calendar button keys off.
enum ShareCameraRollSelection: Equatable, Hashable, Sendable {
    /// The whole library, newest first - the existing unscoped fetch, unchanged.
    case recents
    /// Browsing albums rather than photos. Nothing to date-filter yet.
    case allAlbums
    /// One album's photos.
    case album(ShareAlbum)

    /// True when photos are on screen, which is exactly when a date filter has something to act on.
    var showsPhotos: Bool {
        self != .allAlbums
    }

    var album: ShareAlbum? {
        if case .album(let album) = self { return album }
        return nil
    }
}

/// The full camera-roll scope: which photos, and optionally from when.
///
/// Album and date are independent and compose into a single fetch, so neither ever overwrites the
/// other.
struct ShareCameraRollScope: Equatable, Sendable {
    var selection: ShareCameraRollSelection = .recents
    var dateWindow: ShareDateWindow?

    /// The album the climber opened from the All Albums grid, if any.
    ///
    /// This is what turns the `All Albums` item into a back item, and it is deliberately separate
    /// from `selection`: choosing Favorites from the shortcuts is the same destination but arrives
    /// without a browser to go back to.
    var browsedAlbum: ShareAlbum?

    static let recents = ShareCameraRollScope()

    var showsPhotos: Bool { selection.showsPhotos }

    /// Dropping the album, keeping any date. Used when a remembered album no longer resolves.
    func clearingAlbum() -> ShareCameraRollScope {
        ShareCameraRollScope(selection: .recents, dateWindow: dateWindow, browsedAlbum: nil)
    }
}
