import Foundation

/// Every title one climber holds right now.
///
/// The rarest title leads the crown on their picture; each other title is a dot beside
/// it on large pictures; all three at once is "Undisputed".
struct ChampionTitles: Equatable, Hashable, Sendable {
    static let none = ChampionTitles([])

    let held: Set<ChampionTitle>

    init(_ held: Set<ChampionTitle>) {
        self.held = held
    }

    var isEmpty: Bool {
        held.isEmpty
    }

    /// The title whose crown the picture wears.
    var leading: ChampionTitle? {
        held.max()
    }

    /// The titles shown as dots under the leading crown, rarest first.
    var others: [ChampionTitle] {
        guard let leading else { return [] }
        return held.filter { $0 != leading }.sorted(by: >)
    }

    var isUndisputed: Bool {
        held.count == ChampionTitle.allCases.count
    }

    func adding(_ title: ChampionTitle) -> ChampionTitles {
        ChampionTitles(held.union([title]))
    }
}
