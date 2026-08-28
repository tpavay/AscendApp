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
            count: { $0.ladder.counts.top1 }
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
            count: { $0.ladder.counts.top10 }
        ),
        ProfileAchievementDefinition(
            id: "top100",
            asset: "LeaderboardTop100",
            tint: ProfileVisualStyle.secondaryText,
            label: ProfileTerminology.topHundredAchievementLabel,
            historyFilter: .band(.top100),
            surfaces: [.ownProfile, .comparison],
            count: { $0.ladder.counts.top100 }
        )
    ]

    static func definitions(
        for surface: ProfileAchievementSurface
    ) -> [ProfileAchievementDefinition] {
        all.filter { $0.surfaces.contains(surface) }
    }

    /// The comparison rows for one matchup, in catalogue order.
    ///
    /// A row is emitted only when both sides can *answer* for that badge and at least one of
    /// them holds it. A side that merely cannot say is not a zero, so ghosting it would claim
    /// they hold none of a badge they may well hold; and a badge neither climber has won is a
    /// row about nothing, which is what would turn two new climbers' first meeting into a
    /// monument to things neither of them has done.
    static func comparisonEntries(
        viewer: ProfileAchievementTally,
        other: ProfileAchievementTally
    ) -> [ProfileAchievementComparisonEntry] {
        definitions(for: .comparison).compactMap { definition in
            guard
                let viewerCount = definition.count(viewer),
                let otherCount = definition.count(other),
                viewerCount > 0 || otherCount > 0
            else { return nil }

            return ProfileAchievementComparisonEntry(
                id: definition.id,
                asset: definition.asset,
                tint: definition.tint,
                label: definition.displayLabel(count: max(viewerCount, otherCount)),
                accessibilityName: definition.accessibilityName,
                viewerCount: viewerCount,
                otherCount: otherCount
            )
        }
    }
}
