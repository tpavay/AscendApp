import Foundation

/// Where a block-list read is allowed to come from.
///
/// The server is authoritative. `cache` is Firestore's own local persistence and
/// is only consulted when the server is unreachable, so an offline device defers
/// to the blocks it already knows about instead of rendering every climber
/// masked.
enum BlockListReadSource: Sendable {
    case server
    case cache
}
