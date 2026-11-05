import Foundation

/// The four pieces of gear 04 shows, picked from the hosted unlock catalogue so the screen follows
/// the month by itself: the event running today, else the latest one that finished, else the next
/// one to open. Nothing about a season is written in code.
struct SellGearSelection: Equatable {
    struct Piece: Equatable, Identifiable {
        let item: UnlockItem
        /// What it takes, as `UnlockCopy` words it: "OPEN ASCEND", "10 CLIMBS", "25K STEPS".
        let requirement: String
        /// The piece's own name, shown with its requirement on the big one.
        let name: String

        var id: String { item.id }
    }

    let event: UnlockEvent
    /// The hardest piece to earn, drawn large in the middle.
    let centerpiece: Piece
    /// Up to three more, in the order the catalogue names them.
    let companions: [Piece]

    var pieces: [Piece] { [centerpiece] + companions }

    /// Steps a centrepiece is worth chasing from: a few climbs of work, not a season of it.
    private static let centerpieceStepFloor = 20_000

    init?(catalog: UnlockCatalog, today: Date, calendar: Calendar = .current) {
        guard let event = Self.event(in: catalog, today: today, calendar: calendar) else { return nil }
        let items = catalog.items(earnedIn: event)
        guard !items.isEmpty else { return nil }

        let centre = items
            .filter { $0.earn.metric == .steps && $0.earn.threshold >= Self.centerpieceStepFloor }
            .min { $0.earn.threshold < $1.earn.threshold }
            ?? items.last
        guard let centre else { return nil }

        let showcase = catalog.showcase(of: event)
        let rest = items.filter { item in !showcase.contains(item) }
        let companions = (showcase + rest)
            .filter { $0 != centre }
            .prefix(3)

        self.event = event
        centerpiece = Self.piece(centre, in: event)
        self.companions = companions.map { Self.piece($0, in: event) }
    }

    private static func piece(_ item: UnlockItem, in event: UnlockEvent) -> Piece {
        Piece(
            item: item,
            requirement: UnlockCopy.threshold(item, in: event).uppercased(),
            name: item.shape.title
        )
    }

    /// The event whose window holds `today`; with none, the one that ended most recently; with
    /// none of those, the one that opens first.
    static func event(in catalog: UnlockCatalog, today: Date, calendar: Calendar = .current) -> UnlockEvent? {
        if let running = catalog.events.first(where: { $0.contains(today, calendar: calendar) }) {
            return running
        }
        let finished = catalog.events
            .compactMap { event in event.interval(in: calendar).map { (event, $0.end) } }
            .filter { $0.1 <= today }
            .max { $0.1 < $1.1 }?
            .0
        if let finished { return finished }
        return catalog.events
            .compactMap { event in event.interval(in: calendar).map { (event, $0.start) } }
            .min { $0.1 < $1.1 }?
            .0
    }
}
