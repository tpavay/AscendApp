import SwiftUI

/// One badge type, declared once.
///
/// Every renderer reads these, so display order, art, tint and wording cannot drift between the
/// own-profile shelf and the comparison rows.
struct ProfileAchievementDefinition: Identifiable, Sendable {
    let id: String
    let asset: String
    let tint: Color
    let label: String
    /// Differs from `label` only where English needs a different word above one.
    let pluralLabel: String
    /// What VoiceOver announces. `#2` reads as a bare number next to the count, so the
    /// placement badges spell their rank out instead.
    let accessibilityName: String
    let historyFilter: ProfileAchievementHistoryFilter?
    /// Which screens draw this badge. Scoping a badge to a surface is this set, not a branch.
    let surfaces: Set<ProfileAchievementSurface>
    /// `nil` means this tally *cannot speak to* this badge - which is not the same as zero, and
    /// is why a banded profile withholds an exact placement rather than guessing it.
    let count: @Sendable (ProfileAchievementTally) -> Int?

    init(
        id: String,
        asset: String,
        tint: Color,
        label: String,
        pluralLabel: String? = nil,
        accessibilityName: String? = nil,
        historyFilter: ProfileAchievementHistoryFilter?,
        surfaces: Set<ProfileAchievementSurface>,
        count: @escaping @Sendable (ProfileAchievementTally) -> Int?
    ) {
        self.id = id
        self.asset = asset
        self.tint = tint
        self.label = label
        self.pluralLabel = pluralLabel ?? label
        self.accessibilityName = accessibilityName ?? label
        self.historyFilter = historyFilter
        self.surfaces = surfaces
        self.count = count
    }

    func displayLabel(count: Int) -> String {
        count == 1 ? label : pluralLabel
    }
}
