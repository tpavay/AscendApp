import SwiftUI

/// One badge type counted for both climbers, ready to draw as a comparison row.
///
/// A count that is present is a known number: a zero here means zero, never "we could not tell".
/// `nil` is the one case where nobody read that side's ladder at all, and it draws as a dash.
struct ProfileAchievementComparisonEntry: Identifiable, Equatable {
    let id: String
    let asset: String
    let tint: Color
    let label: String
    let accessibilityName: String
    let viewerCount: Int?
    let otherCount: Int?
}
