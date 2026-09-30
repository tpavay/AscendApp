import Foundation

/// Every sentence the recap says, decided outside the views so each variant is testable.
///
/// Declarative and specific: the numbers are the point, and nothing begs.
enum PeriodRecapCopy {
    /// `WEEK 38 · SEP 14-20, 2026` or `AUGUST 2026`.
    static func periodLabel(for period: LeaderboardPeriod) -> String {
        switch period.timeFrame {
        case .weekly:
            return "WEEK \(ChampionTitleLine.weekNumber(of: period)) · \(compactWindow(for: period)), \(year(of: period))"
        case .monthly:
            return LeaderboardPeriod.datedMonthStyle.format(period.startAt).uppercased()
        default:
            return ChampionTitleLine.periodName(for: period)
        }
    }

    /// `SEP 14-20`, or `AUG 31-SEP 6` across a month boundary. UTC-pinned like every window.
    static func compactWindow(for period: LeaderboardPeriod) -> String {
        guard let endAt = period.endAt else { return period.windowLabel.uppercased() }
        let lastDay = endAt.addingTimeInterval(-1)
        let calendar = LeaderboardPeriod.labelCalendar
        let sameMonth = calendar.component(.month, from: period.startAt) == calendar.component(.month, from: lastDay)
        let start = LeaderboardPeriod.dayStyle.format(period.startAt).uppercased()
        let end = sameMonth
            ? String(calendar.component(.day, from: lastDay))
            : LeaderboardPeriod.dayStyle.format(lastDay).uppercased()
        return "\(start)-\(end)"
    }

    /// `Sep 14-20` for a sentence, with the same boundaries as `compactWindow`.
    static func sentenceWindow(for period: LeaderboardPeriod) -> String {
        switch period.timeFrame {
        case .weekly:
            return compactWindow(for: period).capitalized
        default:
            return ChampionTitleLine.periodName(for: period).capitalized
        }
    }

    /// `week 38` or `August`, as the subject of a sentence.
    static func periodSubject(for period: LeaderboardPeriod) -> String {
        switch period.timeFrame {
        case .weekly: "week \(ChampionTitleLine.weekNumber(of: period))"
        default: ChampionTitleLine.periodName(for: period).capitalized
        }
    }

    /// `YOUR WEEK` or `YOUR MONTH`.
    static func yourSectionLabel(for period: LeaderboardPeriod) -> String {
        period.timeFrame == .monthly ? "YOUR MONTH" : "YOUR WEEK"
    }

    /// `EARNED THIS WEEK` or `EARNED IN AUGUST`.
    static func earnedSectionLabel(for period: LeaderboardPeriod) -> String {
        period.timeFrame == .monthly
            ? "EARNED IN \(ChampionTitleLine.periodName(for: period))"
            : "EARNED THIS WEEK"
    }

    /// `+2 on last week` - only ever a gain. A quieter week says nothing rather than a loss.
    static func gainLine(current: Int, previous: Int?, period: LeaderboardPeriod) -> String? {
        guard let previous, current > previous else { return nil }
        let reference = period.timeFrame == .monthly
            ? (period.previous.map { ChampionTitleLine.periodName(for: $0).capitalized } ?? "last month")
            : "last week"
        return "+\((current - previous).formatted()) on \(reference)"
    }

    /// `of 38 climbers · Top 10%`
    static func rankContext(climberCount: Int, percentileBand: String?) -> String {
        let climbers = "of \(climberCount.formatted()) \(climberCount == 1 ? "climber" : "climbers")"
        guard let percentileBand else { return climbers }
        return "\(climbers) · \(percentileBand)"
    }

    /// The badge an award rank earned, named in words.
    static func award(rank: Int, period: LeaderboardPeriod) -> (asset: String, title: String, detail: String) {
        let board = period.timeFrame == .monthly ? "the monthly board" : "the weekly board"
        switch rank {
        case 1: return ("LeaderboardCrown", "Champion", "#1 on \(board)")
        case 2: return ("LeaderboardSilverMedal", "#2 finish", "Silver on \(board)")
        case 3: return ("LeaderboardBronzeMedal", "#3 finish", "Bronze on \(board)")
        case 4...10: return ("LeaderboardTop10", "Top 10 finish", "#\(rank) on \(board)")
        default: return ("LeaderboardTop100", "Top 100 finish", "#\(rank) on \(board)")
        }
    }

    /// What the climber earned in a period, each badge named in words: the award rank, then
    /// up to three First Ascents. `climbName` names a First Ascent the server stored without
    /// a name.
    static func earnedRows(
        for active: PeriodRecap.Active,
        period: LeaderboardPeriod,
        climbName: (String) -> String?
    ) -> [PeriodRecapEarnedRow] {
        var rows: [PeriodRecapEarnedRow] = []
        if let awardRank = active.awardRank {
            let award = award(rank: awardRank, period: period)
            rows.append(PeriodRecapEarnedRow(id: "award", asset: award.asset, title: award.title, detail: award.detail))
        }
        for firstAscent in active.firstAscents.prefix(3) {
            let name = firstAscent.name ?? climbName(firstAscent.climbId)
            rows.append(PeriodRecapEarnedRow(
                id: "first-ascent-\(firstAscent.climbId)",
                asset: "FirstAscentBadgeDetailed",
                title: "First Ascent",
                detail: name.map { "\($0) - first to finish it" } ?? "First to finish it"
            ))
        }
        return rows
    }

    /// `Zoe R. took the crown.`, `You took the crown.`, `Zoe R. & Noah G. took the crown.`
    static func crownHeadline(names: [String], viewerIsChampion: Bool) -> String {
        guard viewerIsChampion else {
            return "\(ChampionNames.joined(names)) took the crown."
        }
        let others = names.dropFirst()
        return others.isEmpty
            ? "You took the crown."
            : "You & \(ChampionNames.joined(Array(others))) took the crown."
    }

    /// `Ezra K. took August.` / `You took week 35.` on the closing page naming both crowns.
    static func crownsHeadline(names: [String], viewerIsChampion: Bool, period: LeaderboardPeriod) -> String {
        let subject = periodSubject(for: period)
        guard viewerIsChampion else {
            return "\(ChampionNames.joined(names)) took \(subject)."
        }
        let others = names.dropFirst()
        return others.isEmpty
            ? "You took \(subject)."
            : "You & \(ChampionNames.joined(Array(others))) took \(subject)."
    }

    /// `836 steps · 9 climbers`, or `tied at exactly 1,776 steps · 9 climbers`.
    static func crownDetail(steps: Int, climberCount: Int, isTie: Bool) -> String {
        let stepsText = "\(steps.formatted()) steps"
        let climbers = "\(climberCount.formatted()) \(climberCount == 1 ? "climber" : "climbers")"
        return isTie ? "Tied at exactly \(stepsText) · \(climbers)" : "\(stepsText) · \(climbers)"
    }

    /// `Your crown shows on your picture everywhere until Sunday, 7 PM.`, with the date once
    /// the end is more than a week out: `until Saturday, October 31, 8 PM.`
    static func reignLine(
        endsAt: Date?,
        now: Date = .now,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String? {
        guard let endsAt else { return nil }
        let base = Date.FormatStyle(locale: locale, timeZone: timeZone)
        let dayStyle = endsAt.timeIntervalSince(now) > 6 * 24 * 60 * 60
            ? base.weekday(.wide).month(.wide).day()
            : base.weekday(.wide)
        let day = endsAt.formatted(dayStyle)
        let time = endsAt.formatted(base.hour())
        return "Your crown shows on your picture everywhere until \(day), \(time)."
    }

    /// `Week 39 is open. Your first climb puts you on the board.`
    static func firstClimbLine(after period: LeaderboardPeriod) -> String {
        guard let next = period.next else { return "Your first climb puts you on the board." }
        return "\(periodSubject(for: next).capitalizedFirst) is open. Your first climb puts you on the board."
    }

    /// `No climbs last week.` / `No climbs in August.`
    static func noClimbsHeadline(for period: LeaderboardPeriod) -> String {
        period.timeFrame == .monthly
            ? "No climbs in \(periodSubject(for: period))."
            : "No climbs last week."
    }

    /// `Last climb: 12 days ago. Week 39 is open.`
    static func noClimbsDetail(lastClimbAt: Date?, period: LeaderboardPeriod, now: Date) -> String {
        let open = period.next.map { "\(periodSubject(for: $0).capitalizedFirst) is open." } ?? ""
        guard let lastClimbAt else { return open }
        let days = max(Int(now.timeIntervalSince(lastClimbAt) / 86_400), 1)
        return "Last climb: \(days) \(days == 1 ? "day" : "days") ago. \(open)"
            .trimmingCharacters(in: .whitespaces)
    }

    /// `Three weeks. Three champions.`
    static func catchUpHeadline(weeks: Int, champions: Int) -> String {
        "\(spelled(weeks).capitalizedFirst) \(weeks == 1 ? "week" : "weeks"). "
            + "\(spelled(champions).capitalizedFirst) \(champions == 1 ? "champion" : "champions")."
    }

    /// `You: #4 · 7,904 steps`, or `You: 7,904 steps` when the period had too few climbers
    /// for a rank.
    static func catchUpYoursLine(_ active: PeriodRecap.Active) -> String {
        let steps = "\(active.steps.formatted()) steps"
        guard let rank = active.awardRank ?? active.rank else { return "You: \(steps)" }
        return "You: #\(rank) · \(steps)"
    }

    /// `Your last climb was Sep 2.`
    static func lastClimbLine(_ lastClimbAt: Date?, timeZone: TimeZone = .current) -> String? {
        guard let lastClimbAt else { return nil }
        let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: timeZone)
            .month(.abbreviated).day()
        return "Your last climb was \(lastClimbAt.formatted(style))."
    }

    private static func spelled(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func year(of period: LeaderboardPeriod) -> String {
        guard let endAt = period.endAt else { return LeaderboardPeriod.yearStyle.format(period.startAt) }
        return LeaderboardPeriod.yearStyle.format(endAt.addingTimeInterval(-1))
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
