import SwiftUI

/// One badge type counted for both climbers, ready to draw as a comparison row.
///
/// Both counts are known numbers: a zero here means zero, never "we could not tell".
struct ProfileAchievementComparisonEntry: Identifiable, Equatable {
    let id: String
    let asset: String
    let tint: Color
    let label: String
    let accessibilityName: String
    let viewerCount: Int
    let otherCount: Int
}
