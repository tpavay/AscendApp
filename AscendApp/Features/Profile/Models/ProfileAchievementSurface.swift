import Foundation

/// Which screen is asking the achievement catalogue for badges.
///
/// The surfaces deliberately draw different source lists. The own profile is where a climber
/// admires their case; the comparison is where two cases are counted against each other, and a
/// badge nobody in the matchup holds is not part of that count.
enum ProfileAchievementSurface: Hashable, CaseIterable, Sendable {
    case ownProfile
    case comparison
}
