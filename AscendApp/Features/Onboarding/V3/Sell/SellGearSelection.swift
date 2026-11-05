import Foundation

/// The gear 04 shows, picked from the hosted unlock catalogue so the screen follows the month by
/// itself: the event running today, else the latest one that finished. Nothing about a season is
/// written in code.
///
/// 11 shows the event's showcase, so 04 never does. An event too small to have gear left over has
/// no selection, and 04 leads with its reasons instead.
struct SellGearSelection: Equatable {
    struct Piece: Equatable, Identifiable {
        let item: UnlockItem
        /// What it takes, as `UnlockCopy` words it and VoiceOver says it: "Open Ascend", "25K steps".
        let spokenRequirement: String
        /// The same words on screen: "OPEN ASCEND", "25K STEPS".
        var requirement: String { spokenRequirement.uppercased() }
        /// The piece's own name, shown with its requirement on the big one.
        let name: String

        var id: String { item.id }
    }

    /// The first step goal at or above ``centerpieceStepFloor``, else the catalogue's last piece,
    /// drawn large in the middle.
    let centerpiece: Piece
    /// Up to three more, in the order the catalogue names them.
    let companions: [Piece]

    var pieces: [Piece] { [centerpiece] + companions }

    /// An event with fewer live items than this shows no gear on 04.
    private static let minimumLiveItems = 7

    /// Steps a centrepiece is worth chasing from: a few climbs of work, not a season of it.
    private static let centerpieceStepFloor = 20_000

    init?(catalog: UnlockCatalog, today: Date) {
        guard let event = Self.event(in: catalog, today: today) else { return nil }
        let items = catalog.items(earnedIn: event)
        guard items.count >= Self.minimumLiveItems else { return nil }

        let showcase = catalog.showcase(of: event)
        let offered = items.filter { !showcase.contains($0) }
        let centre = offered
            .filter { $0.earn.metric == .steps && $0.earn.threshold >= Self.centerpieceStepFloor }
            .min { $0.earn.threshold < $1.earn.threshold }
            ?? offered.last
        guard let centre else { return nil }

        centerpiece = Self.piece(centre, in: event)
        companions = offered
            .filter { $0 != centre }
            .prefix(3)
            .map { Self.piece($0, in: event) }
    }

    private static func piece(_ item: UnlockItem, in event: UnlockEvent) -> Piece {
        Piece(
            item: item,
            spokenRequirement: UnlockCopy.threshold(item, in: event),
            name: item.shape.title
        )
    }

    /// The event whose window holds `today`; with none, the one that ended most recently.
    static func event(in catalog: UnlockCatalog, today: Date) -> UnlockEvent? {
        if let running = catalog.events.first(where: { $0.contains(today) }) {
            return running
        }
        return catalog.events
            .compactMap { event in event.interval(in: .current).map { (event, $0.end) } }
            .filter { $0.1 <= today }
            .max { $0.1 < $1.1 }?
            .0
    }
}
