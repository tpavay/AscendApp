import Foundation

/// The words that name the rarest title a climber holds right now, e.g. `LAST WEEK'S CHAMPION`.
///
/// The comparison screen prints it under a name. A held title is only ever the period
/// that just closed (or the live all-time lead), so it is named relative to now - an
/// older title never appears here; history lives on past boards and the CHAMPION history.
/// Several titles name only the rarest - the others are the dots on the picture - and a
/// title shared on an exact tie is a co-championship.
struct ChampionTitleLine: Equatable, Sendable {
    let text: String
    let leadingTitle: ChampionTitle

    static func make(
        titles: ChampionTitles,
        reigns: [ChampionTitle: ChampionReign]
    ) -> ChampionTitleLine? {
        guard let leading = ([titles.leading].compactMap { $0 } + titles.others)
            .first(where: { reigns[$0] != nil }),
              let reign = reigns[leading] else { return nil }
        let isShared = reign.result.championUserIds.count > 1
        return ChampionTitleLine(
            text: "\(relativeName(for: leading)) \(isShared ? "CO-CHAMPION" : "CHAMPION")",
            leadingTitle: leading
        )
    }

    /// A reigning title named relative to now: `LAST WEEK'S`, `LAST MONTH'S`, `LAST YEAR'S`,
    /// or `ALL-TIME` for the live lead.
    static func relativeName(for title: ChampionTitle) -> String {
        switch title {
        case .weekly: "LAST WEEK'S"
        case .monthly: "LAST MONTH'S"
        case .yearly: "LAST YEAR'S"
        case .allTime: "ALL-TIME"
        }
    }

    /// The period a title was won in, as its champion is named: `WEEK 38`, `AUGUST`, `2026`.
    static func periodName(for period: LeaderboardPeriod) -> String {
        switch period.timeFrame {
        case .weekly:
            return "WEEK \(weekNumber(of: period))"
        case .monthly:
            return LeaderboardPeriod.monthStyle.format(period.startAt).uppercased()
        case .yearly:
            return LeaderboardPeriod.yearStyle.format(period.startAt)
        case .allTime:
            return "ALL-TIME"
        case .daily:
            return period.windowLabel.uppercased()
        }
    }

    /// The ISO-style week number the period key carries (`2026-W38` is 38), so the name
    /// always agrees with the key the server froze the result under.
    static func weekNumber(of period: LeaderboardPeriod) -> Int {
        guard let marker = period.key.range(of: "-W"),
              let week = Int(period.key[marker.upperBound...]) else {
            return 0
        }
        return week
    }
}
