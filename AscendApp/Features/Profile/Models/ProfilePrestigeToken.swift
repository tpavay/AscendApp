import SwiftUI

struct ProfilePrestigeToken: Identifiable {
    let id: String
    let asset: String
    let tint: Color
    let count: Int
    let label: String
    /// What VoiceOver announces. `#2` reads as a bare number next to the count, so the
    /// placement badges spell their rank out instead.
    let accessibilityName: String
    let historyFilter: ProfileAchievementHistoryFilter?

    init(
        id: String,
        asset: String,
        tint: Color,
        count: Int,
        label: String,
        accessibilityName: String? = nil,
        historyFilter: ProfileAchievementHistoryFilter?
    ) {
        self.id = id
        self.asset = asset
        self.tint = tint
        self.count = count
        self.label = label
        self.accessibilityName = accessibilityName ?? label
        self.historyFilter = historyFilter
    }

    init(definition: ProfileAchievementDefinition, count: Int) {
        self.init(
            id: definition.id,
            asset: definition.asset,
            tint: definition.tint,
            count: count,
            label: definition.displayLabel(count: count),
            accessibilityName: definition.accessibilityName,
            historyFilter: definition.historyFilter
        )
    }

    /// The badges this climber has actually earned, in catalogue order.
    ///
    /// A definition that returns `nil` cannot be spoken to by this tally - a banded profile and
    /// the exact placements - and one that returns zero has not been earned yet. A shelf shows
    /// neither.
    static func tokens(
        for tally: ProfileAchievementTally,
        surface: ProfileAchievementSurface
    ) -> [ProfilePrestigeToken] {
        ProfileAchievementCatalogue.definitions(for: surface).compactMap { definition in
            guard let count = definition.count(tally), count > 0 else { return nil }
            return ProfilePrestigeToken(definition: definition, count: count)
        }
    }
}
