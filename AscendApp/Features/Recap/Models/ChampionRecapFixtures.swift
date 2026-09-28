import Foundation

#if DEBUG || STAGING
/// Sample champions and recaps for the Debug preview and the evidence renders.
///
/// Built through the same `PeriodRecapStoryBuilder` the app uses, so a preview can never
/// show a story the real data could not produce. Never compiled into a Release build.
struct ChampionRecapFixtures {
    enum Variant: String, CaseIterable, Identifiable {
        case week = "Week: you finished #3"
        case coronation = "Week: you took the crown"
        case coChampions = "Week: co-champions (exact tie)"
        case weekAndMonth = "Week and month closed together"
        case catchUp = "Back after three weeks"
        case noClimbs = "A week with no climbs"
        case neverClimbed = "Never climbed"

        var id: String { rawValue }
    }

    static let names: [(id: String, name: String)] = [
        ("fixture-zoe", "Zoe Ramirez"),
        ("fixture-maya", "Maya Chen"),
        ("fixture-noah", "Noah Grant"),
        ("fixture-ezra", "Ezra Kim"),
        ("fixture-vera", "Vera Lind")
    ]

    let viewerId: String
    /// The viewer's name on their own placings - the signed-in account's.
    var viewerName = "Tyler Pavay"
    var now: Date = .now

    func placing(_ index: Int, rank: Int, steps: Int, climbs: Int, asViewer: Bool = false) -> LeaderboardPlacing {
        let person = Self.names[index]
        return LeaderboardPlacing(
            userId: asViewer ? viewerId : person.id,
            unresolvedIdentity: UnresolvedUserIdentity(
                displayName: asViewer ? viewerName : person.name,
                photoURL: nil,
                isSynthetic: !asViewer
            ),
            rank: rank,
            totalSteps: steps,
            totalWorkouts: climbs
        )
    }

    /// The week and month that closed most recently before `now`.
    func periods() -> (week: LeaderboardPeriod, month: LeaderboardPeriod) {
        (
            LeaderboardTimeFrame.weekly.previousPeriod(referenceDate: now)!,
            LeaderboardTimeFrame.monthly.previousPeriod(referenceDate: now)!
        )
    }

    func result(
        period: LeaderboardPeriod,
        placings: [LeaderboardPlacing],
        climberCount: Int,
        community: LeaderboardResult.Community,
        mostClimbs: LeaderboardResult.MostClimbs?
    ) -> PeriodRecapResultBundle {
        PeriodRecapResultBundle(
            result: LeaderboardResult(
                period: period,
                climberCount: climberCount,
                championUserIds: placings.filter { $0.rank == 1 }.map(\.userId),
                podiumUserIds: placings.filter { $0.rank <= 3 }.map(\.userId),
                mostClimbs: mostClimbs,
                community: community
            ),
            placings: placings
        )
    }

    func weekBundle(period: LeaderboardPeriod, viewerPlaces: Bool = true, viewerWins: Bool, tie: Bool = false) -> PeriodRecapResultBundle {
        let placings: [LeaderboardPlacing] = if viewerWins {
            [
                placing(0, rank: 1, steps: 8_836, climbs: 6, asViewer: viewerPlaces),
                placing(1, rank: 2, steps: 8_120, climbs: 5),
                placing(2, rank: 3, steps: 7_904, climbs: 4),
                placing(3, rank: 4, steps: 7_100, climbs: 9)
            ]
        } else if tie {
            [
                placing(0, rank: 1, steps: 1_776, climbs: 2),
                placing(2, rank: 1, steps: 1_776, climbs: 3),
                placing(1, rank: 3, steps: 1_402, climbs: 2, asViewer: viewerPlaces),
                placing(3, rank: 4, steps: 980, climbs: 9)
            ]
        } else {
            [
                placing(0, rank: 1, steps: 8_836, climbs: 6),
                placing(1, rank: 2, steps: 8_120, climbs: 5),
                placing(2, rank: 3, steps: 7_904, climbs: 4, asViewer: viewerPlaces),
                placing(3, rank: 4, steps: 7_100, climbs: 9)
            ]
        }
        let mostClimbsUser = placings.first { $0.totalWorkouts == 9 }?.userId
        return result(
            period: period,
            placings: placings,
            climberCount: 38,
            community: .init(climbers: 38, climbs: 214, steps: 1_204_880, floors: 60_244),
            mostClimbs: mostClimbsUser.map { .init(count: 9, userIds: [$0]) }
        )
    }

    func monthBundle(period: LeaderboardPeriod) -> PeriodRecapResultBundle {
        result(
            period: period,
            placings: [
                placing(3, rank: 1, steps: 52_300, climbs: 31),
                placing(1, rank: 2, steps: 48_950, climbs: 22),
                placing(4, rank: 3, steps: 41_200, climbs: 19)
            ],
            climberCount: 61,
            community: .init(climbers: 61, climbs: 902, steps: 5_310_400, floors: 265_520),
            mostClimbs: .init(count: 31, userIds: ["fixture-ezra"])
        )
    }

    func active(rank: Int?, climbers: Int, steps: Int, climbs: Int, awardRank: Int?) -> PeriodRecap.Active {
        PeriodRecap.Active(
            rank: rank,
            climberCount: rank == nil ? nil : climbers,
            percentileBand: rank.map { $0 <= 4 ? "Top 10%" : "Top 25%" },
            climbs: climbs,
            steps: steps,
            floors: steps / 20,
            previousClimbs: max(climbs - 2, 0),
            previousSteps: max(steps - 3_100, 0),
            awardRank: awardRank,
            firstAscents: [PeriodRecap.FirstAscent(climbId: "tallinn-tv-tower", name: "Tallinn TV Tower")],
            landmarksFinished: ["Tallinn TV Tower"]
        )
    }

    func recap(
        period: LeaderboardPeriod,
        variant: PeriodRecap.Variant,
        active: PeriodRecap.Active? = nil,
        lastClimbAt: Date? = nil
    ) -> PeriodRecap {
        PeriodRecap(
            id: PeriodRecap.documentID(cadence: period.timeFrame, periodKey: period.key),
            period: period,
            variant: variant,
            active: active,
            inactive: variant == .inactive ? PeriodRecap.Inactive(
                gapCount: 2,
                lastClimbAt: lastClimbAt,
                suggestedClimbId: "tallinn-tv-tower",
                suggestedClimbName: "Tallinn TV Tower"
            ) : nil,
            seenAt: nil
        )
    }

    let bestEfforts = [
        PeriodRecapBestEffort(title: "Fastest 1,000 Steps", value: "4:12"),
        PeriodRecapBestEffort(title: "Most Steps in 10 Min", value: "1,210")
    ]

    // MARK: - Stories

    func story(_ variant: Variant) -> PeriodRecapStory? {
        let (week, month) = periods()
        var recaps: [PeriodRecap] = []
        var results: [String: PeriodRecapResultBundle] = [:]
        var bestEffortsByRecap: [String: [PeriodRecapBestEffort]] = [:]

        switch variant {
        case .week, .coronation, .coChampions:
            let wins = variant == .coronation
            let tie = variant == .coChampions
            let recap = recap(
                period: week,
                variant: .active,
                active: active(rank: wins ? 1 : 3, climbers: 38, steps: wins ? 8_836 : 7_904, climbs: 5, awardRank: wins ? 1 : 3)
            )
            recaps = [recap]
            results[recap.resultID] = weekBundle(period: week, viewerWins: wins, tie: tie)
            bestEffortsByRecap[recap.id] = bestEfforts
        case .weekAndMonth:
            let weekRecap = recap(period: week, variant: .active, active: active(rank: 3, climbers: 38, steps: 7_904, climbs: 5, awardRank: 3))
            let monthRecap = recap(period: month, variant: .active, active: active(rank: 2, climbers: 61, steps: 46_200, climbs: 18, awardRank: 2))
            recaps = [weekRecap, monthRecap]
            results[weekRecap.resultID] = weekBundle(period: week, viewerWins: false)
            results[monthRecap.resultID] = monthBundle(period: month)
            bestEffortsByRecap[weekRecap.id] = bestEfforts
        case .catchUp:
            var period = week
            for index in 0..<3 {
                let recap = recap(
                    period: period,
                    variant: .inactive,
                    lastClimbAt: now.addingTimeInterval(-26 * 86_400)
                )
                recaps.append(recap)
                results[recap.resultID] = weekBundle(
                    period: period,
                    viewerPlaces: false,
                    viewerWins: false,
                    tie: index == 2
                )
                period = period.previous!
            }
            let monthRecap = recap(period: month, variant: .inactive, lastClimbAt: now.addingTimeInterval(-26 * 86_400))
            recaps.append(monthRecap)
            results[monthRecap.resultID] = monthBundle(period: month)
        case .noClimbs:
            let recap = recap(period: week, variant: .inactive, lastClimbAt: now.addingTimeInterval(-12 * 86_400))
            recaps = [recap]
            results[recap.resultID] = weekBundle(period: week, viewerPlaces: false, viewerWins: false)
        case .neverClimbed:
            let recap = recap(period: week, variant: .neverClimbed)
            recaps = [recap]
            results[recap.resultID] = weekBundle(period: week, viewerPlaces: false, viewerWins: false)
        }

        return PeriodRecapStoryBuilder.build(
            recaps: recaps,
            results: results,
            bestEfforts: bestEffortsByRecap,
            viewerId: viewerId,
            now: now
        )
    }

    /// Reigns that crown the viewer with the chosen titles, for previewing their own crown.
    func reigns(crowning titles: Set<ChampionTitle>) -> [ChampionTitle: ChampionReign] {
        var reigns: [ChampionTitle: ChampionReign] = [:]
        for title in titles {
            guard let period = title.isFinalized
                ? title.timeFrame.previousPeriod(referenceDate: now)
                : title.timeFrame.currentPeriod(referenceDate: now) else { continue }
            let champion = placing(0, rank: 1, steps: title == .weekly ? 8_836 : 52_300, climbs: 6, asViewer: true)
            let bundle = result(
                period: period,
                placings: [champion],
                climberCount: 38,
                community: .init(climbers: 38, climbs: 214, steps: 1_204_880, floors: 60_244),
                mostClimbs: nil
            )
            reigns[title] = ChampionReign(title: title, result: bundle.result, champions: [champion])
        }
        return reigns
    }
}
#endif
