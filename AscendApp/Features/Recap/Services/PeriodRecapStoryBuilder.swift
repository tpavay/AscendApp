import Foundation

/// A closed period's frozen result together with the placings the recap names: the
/// champions, the rest of the podium, and the most-climbs leaders.
struct PeriodRecapResultBundle: Equatable, Sendable {
    let result: LeaderboardResult
    let placings: [LeaderboardPlacing]
}

/// Decides what a climber's recap shows. Pure, so every variant is testable without a view.
enum PeriodRecapStoryBuilder {
    static let maxCatchUpWeeks = 4
    static let maxCatchUpMonths = 2

    /// Builds the story for every unseen recap, or nil when there is nothing to show.
    ///
    /// - Two or more unseen weeks with no climbing in the latest fold into one catch-up page.
    /// - Otherwise the latest week and, when it closed alongside, the latest month: month
    ///   first, each as everyone's period then yours, ending on one page naming both crowns.
    /// - A period without climbs is one short page; a climber who has never climbed sees
    ///   everyone's period and the crown, ending on their first climb.
    static func build(
        recaps: [PeriodRecap],
        results: [String: PeriodRecapResultBundle],
        bestEfforts: [String: [PeriodRecapBestEffort]] = [:],
        viewerId: String?,
        now: Date
    ) -> PeriodRecapStory? {
        let unseen = recaps
            .filter { $0.seenAt == nil && ($0.period.endAt ?? .distantFuture) <= now }
            .sorted { ($0.period.endAt ?? .distantPast) > ($1.period.endAt ?? .distantPast) }
        guard !unseen.isEmpty else { return nil }

        let weeks = unseen.filter { $0.cadence == .weekly }
        let months = unseen.filter { $0.cadence == .monthly }
        let recapIDs = unseen.map(\.id)
        let isFirstClimbInvitation = unseen.first?.variant == .neverClimbed

        if weeks.count >= 2, weeks.first?.variant != .active {
            return catchUpStory(
                weeks: Array(weeks.prefix(maxCatchUpWeeks)),
                months: Array(months.prefix(maxCatchUpMonths)),
                results: results,
                viewerId: viewerId,
                recapIDs: recapIDs,
                isFirstClimbInvitation: isFirstClimbInvitation,
                now: now
            )
        }

        let featured = [months.first, weeks.first].compactMap { $0 }
        var pages: [PeriodRecapStory.Page] = []
        var chapters: [PeriodRecapStory.Chapter] = []
        var crowns: [PeriodRecapCrown] = []
        var endsWithShortPage = false

        for recap in featured {
            let chapterStart = pages.count
            let bundle = results[recap.resultID]
            let periodCrown = bundle.flatMap { Self.crown(from: $0, viewerId: viewerId) }
            let community = bundle?.result.community

            switch recap.variant {
            case .active:
                if let community {
                    pages.append(.everyone(PeriodRecapCommunity(period: recap.period, community: community)))
                }
                if let active = recap.active {
                    pages.append(.yours(PeriodRecapPersonal(
                        period: recap.period,
                        recap: active,
                        bestEfforts: bestEfforts[recap.id] ?? []
                    )))
                }
                endsWithShortPage = false
            case .inactive:
                pages.append(.noClimbs(PeriodRecapNoClimbs(
                    period: recap.period,
                    inactive: recap.inactive ?? PeriodRecap.Inactive(
                        gapCount: 1,
                        lastClimbAt: nil,
                        suggestedClimbId: nil,
                        suggestedClimbName: nil
                    ),
                    community: community ?? .empty,
                    crown: periodCrown
                )))
                endsWithShortPage = true
            case .neverClimbed:
                if let community {
                    pages.append(.everyone(PeriodRecapCommunity(period: recap.period, community: community)))
                }
                endsWithShortPage = false
            }

            if let periodCrown { crowns.append(periodCrown) }
            if pages.count > chapterStart {
                chapters.append(PeriodRecapStory.Chapter(
                    label: chapterLabel(for: recap.period),
                    pageRange: chapterStart..<pages.count
                ))
            }
        }

        if featured.count > 1, !crowns.isEmpty {
            pages.append(.crowns(crowns))
        } else if featured.count == 1, !endsWithShortPage, let crown = crowns.first {
            pages.append(.crown(crown))
        }
        guard !pages.isEmpty else { return nil }

        // The closing crown page belongs to the last chapter, so its bar reads complete.
        if featured.count > 1, let last = chapters.last {
            chapters[chapters.count - 1] = PeriodRecapStory.Chapter(
                label: last.label,
                pageRange: last.pageRange.lowerBound..<pages.count
            )
        }

        return PeriodRecapStory(
            id: recapIDs.joined(separator: "+"),
            pages: pages,
            chapters: featured.count > 1 ? chapters : [],
            recapIDs: recapIDs,
            isFirstClimbInvitation: isFirstClimbInvitation
        )
    }

    /// The recap IDs whose results a story may name - every unseen recap, newest first.
    static func resultIDs(for recaps: [PeriodRecap]) -> [String] {
        let unseen = recaps
            .filter { $0.seenAt == nil }
            .sorted { ($0.period.endAt ?? .distantPast) > ($1.period.endAt ?? .distantPast) }
        let weeks = unseen.filter { $0.cadence == .weekly }.prefix(maxCatchUpWeeks)
        let months = unseen.filter { $0.cadence == .monthly }.prefix(maxCatchUpMonths)
        var seen = Set<String>()
        return (Array(weeks) + Array(months))
            .map(\.resultID)
            .filter { seen.insert($0).inserted }
    }

    static func crown(from bundle: PeriodRecapResultBundle, viewerId: String?) -> PeriodRecapCrown? {
        guard let title = bundle.result.title, bundle.result.hasChampion else { return nil }
        let byUser = Dictionary(
            bundle.placings.map { ($0.userId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let championIds = bundle.result.championUserIds
        let champions = championIds.compactMap { byUser[$0] }
        guard !champions.isEmpty else { return nil }

        let runnersUp = bundle.placings
            .filter { (2...3).contains($0.rank) && !championIds.contains($0.userId) }
            .sorted { ($0.rank, $0.userId) < ($1.rank, $1.userId) }
        let mostClimbs = (bundle.result.mostClimbs?.userIds ?? []).compactMap { byUser[$0] }

        return PeriodRecapCrown(
            title: title,
            period: bundle.result.period,
            climberCount: bundle.result.climberCount,
            champions: champions,
            runnersUp: Array(runnersUp.prefix(2)),
            mostClimbs: mostClimbs,
            mostClimbsCount: bundle.result.mostClimbs?.count,
            viewerIsChampion: viewerId.map(championIds.contains) ?? false
        )
    }

    static func chapterLabel(for period: LeaderboardPeriod) -> String {
        ChampionTitleLine.periodName(for: period)
    }

    private static func catchUpStory(
        weeks: [PeriodRecap],
        months: [PeriodRecap],
        results: [String: PeriodRecapResultBundle],
        viewerId: String?,
        recapIDs: [String],
        isFirstClimbInvitation: Bool,
        now: Date
    ) -> PeriodRecapStory? {
        let lines = (weeks + months)
            .sorted { ($0.period.endAt ?? .distantPast) > ($1.period.endAt ?? .distantPast) }
            .compactMap { recap -> PeriodRecapCatchUp.Line? in
                guard let bundle = results[recap.resultID],
                      let crown = Self.crown(from: bundle, viewerId: viewerId) else { return nil }
                let reigning = recap.cadence.previousPeriod(referenceDate: now)?.key == recap.period.key
                return PeriodRecapCatchUp.Line(crown: crown, isReigning: reigning)
            }
        let lastClimbAt = weeks.compactMap { $0.inactive?.lastClimbAt }.max()

        return PeriodRecapStory(
            id: recapIDs.joined(separator: "+"),
            pages: [.catchUp(PeriodRecapCatchUp(
                missedWeeks: weeks.count,
                lastClimbAt: lastClimbAt,
                lines: lines
            ))],
            chapters: [],
            recapIDs: recapIDs,
            isFirstClimbInvitation: isFirstClimbInvitation
        )
    }
}
