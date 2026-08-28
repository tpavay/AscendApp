import Foundation

/// One album offered by the share composer's background picker.
///
/// A value type rather than a `PHAssetCollection` so the album list can cross actor boundaries and
/// be reasoned about in tests without a photo library. The `id` is the collection's
/// `localIdentifier`, which is what re-resolves it at fetch time and what survives in `@AppStorage`.
struct ShareAlbum: Identifiable, Equatable, Hashable, Sendable {
    /// Where the album came from, which decides how the grid groups it.
    enum Kind: Equatable, Hashable, Sendable {
        /// An album the climber made themselves.
        case user
        /// One of the curated smart albums iOS generates.
        case smart
    }

    let id: String
    let title: String
    /// A real fetched count, never `PHAssetCollection.estimatedAssetCount` - the SDK documents that
    /// as an estimate that returns `NSNotFound` when it cannot answer quickly, and a tile rendering
    /// "not found photos" is worse than no tile.
    let count: Int
    /// `PHAssetCollection.endDate`, already computed by PhotoKit. This is what earns an album its
    /// slot in the filter row without probing every album for its newest asset.
    let newestAssetDate: Date?
    let kind: Kind

    var isEmpty: Bool { count == 0 }
}
