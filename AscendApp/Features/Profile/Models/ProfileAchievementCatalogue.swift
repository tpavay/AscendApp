import SwiftUI

/// Every badge Ascend draws, in one array.
///
/// Adding a badge is one entry. Removing one is deleting that entry. Showing a badge on only
/// some screens is `surfaces`. Nothing branches per badge anywhere else.
///
/// This deliberately stops short of a hosted file like the climb catalogue: badge art ships as a
/// bundled image asset and the counts are server-derived from finalized achievement records, so
/// a hosted entry would promise content-only additions neither the binary nor the backend could
/// deliver.
enum ProfileAchievementCatalogue {
    /// Array order IS display order, on every surface.
    static let all: [ProfileAchievementDefinition] = [
        ProfileAchievementDefinition(
            id: "first-ascents",
            asset: "FirstAscentBadgeDetailed",
            tint: ProfileVisualStyle.gold,
            label: "First Ascent",
            pluralLabel: "First Ascents",
            historyFilter: nil,
            surfaces: [.ownProfile],
            count: { $0.firstAscentsHeld }
        ),
        ProfileAchievementDefinition(
            id: "top1",
            asset: "LeaderboardCrown",
            tint: ProfileVisualStyle.gold,
            label: ProfileTerminology.topOneAchievementLabel,
            historyFilter: .band(.top1),
            surfaces: [.ownProfile, .comparison],
            count: { $0.ladder.bandFinishes(.top1) }
        ),
        ProfileAchievementDefinition(
            id: "place2",
            asset: "LeaderboardSilverMedal",
            tint: ProfileVisualStyle.silver,
            label: ProfileTerminology.secondPlaceAchievementLabel,
            accessibilityName: ProfileTerminology.secondPlaceAccessibilityName,
            historyFilter: .placement(2),
            surfaces: [.ownProfile, .comparison],
            count: { $0.ladder.secondPlaceFinishes }
        ),
        ProfileAchievementDefinition(
            id: "place3",
            asset: "LeaderboardBronzeMedal",
            tint: ProfileVisualStyle.bronze,
            label: ProfileTerminology.thirdPlaceAchievementLabel,
            accessibilityName: ProfileTerminology.thirdPlaceAccessibilityName,
            historyFilter: .placement(3),
            surfaces: [.ownProfile, .comparison],
            count: { $0.ladder.thirdPlaceFinishes }
        ),
        ProfileAchievementDefinition(
            id: "top10",
            asset: "LeaderboardTop10",
            tint: ProfileVisualStyle.gold,
            label: ProfileTerminology.topTenAchievementLabel,
            historyFilter: .band(.top10),
            surfaces: [.ownProfile, .comparison],
            count: { $0.ladder.bandFinishes(.top10) }
        ),
        ProfileAchievementDefinition(
            id: "top100",
            asset: "LeaderboardTop100",
            tint: ProfileVisualStyle.secondaryText,
            label: ProfileTerminology.topHundredAchievementLabel,
            historyFilter: .band(.top100),
            surfaces: [.ownProfile, .comparison],
            count: { $0.ladder.bandFinishes(.top100) }
        )
    ]

    static func definitions(
        for surface: ProfileAchievementSurface
    ) -> [ProfileAchievementDefinition] {
        all.filter { $0.surfaces.contains(surface) }
    }

    /// The comparison rows for one matchup, in catalogue order.
    ///
    /// A row is emitted only when at least one side is *known* to hold the badge. A badge
    /// neither climber has won is a row about nothing, which is what would turn two new
    /// climbers' first meeting into a monument to things neither of them has done.
    ///
    /// The two silences a side can return are deliberately not the same thing. A ladder that
    /// was never read cannot be given a zero it did not earn, so it renders as a dash beside
    /// the other climber's real count. A readable ladder that answers `nil` is the banded
    /// `profile_stats` fallback, whose taxonomy simply cannot tell a #2 from a #3 - nothing
    /// failed there, so that row is dropped entirely rather than dashed.
    static func comparisonEntries(
        viewer: ProfileAchievementTally,
        other: ProfileAchievementTally
    ) -> [ProfileAchievementComparisonEntry] {
        definitions(for: .comparison).compactMap { definition in
            let viewerSide = sideCount(definition, for: viewer)
            let otherSide = sideCount(definition, for: other)

            guard viewerSide != .cannotSay, otherSide != .cannotSay else { return nil }

            let viewerCount = viewerSide.knownCount
            let otherCount = otherSide.knownCount
            guard (viewerCount ?? 0) > 0 || (otherCount ?? 0) > 0 else { return nil }

            return ProfileAchievementComparisonEntry(
                id: definition.id,
                asset: definition.asset,
                tint: definition.tint,
                label: definition.displayLabel(count: max(viewerCount ?? 0, otherCount ?? 0)),
                accessibilityName: definition.accessibilityName,
                viewerCount: viewerCount,
                otherCount: otherCount
            )
        }
    }

    /// What one side can say about one badge.
    private enum SideCount: Equatable {
        case known(Int)
        /// The read failed, so the side is drawn as a dash rather than guessed at.
        case unreadable
        /// The read worked but its taxonomy is coarser than this badge, so the row is dropped.
        case cannotSay

        var knownCount: Int? {
            if case .known(let count) = self { return count }
            return nil
        }
    }

    private static func sideCount(
        _ definition: ProfileAchievementDefinition,
        for tally: ProfileAchievementTally
    ) -> SideCount {
        if let count = definition.count(tally) {
            return .known(count)
        }
        return tally.ladder.isReadable ? .cannotSay : .unreadable
    }
}
