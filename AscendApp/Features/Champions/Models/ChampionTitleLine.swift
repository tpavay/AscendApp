import Foundation

/// The words that name a climber's titles, e.g. `WEEK 38 CHAMPION`.
///
/// The comparison screen prints it under the other climber's name; the strip and the
/// recap print one title's name. Several titles lead with the rarest, and all three at
/// once is `UNDISPUTED`.
struct ChampionTitleLine: Equatable, Sendable {
    let text: String
    let leadingTitle: ChampionTitle

    static func make(
        titles: ChampionTitles,
        reigns: [ChampionTitle: ChampionReign]
    ) -> ChampionTitleLine? {
        guard let leading = titles.leading else { return nil }
        if titles.isUndisputed {
            return ChampionTitleLine(text: "UNDISPUTED CHAMPION", leadingTitle: leading)
        }

        let names = ([leading] + titles.others).compactMap { title in
            reigns[title].map { periodName(for: $0.result.period) }
        }
        guard !names.isEmpty else { return nil }
        return ChampionTitleLine(
            text: "\(names.joined(separator: " & ")) CHAMPION",
            leadingTitle: leading
        )
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
