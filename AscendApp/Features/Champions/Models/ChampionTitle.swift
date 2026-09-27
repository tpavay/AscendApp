import SwiftUI

/// A title the Steps board awards when a period closes: weekly gold, monthly diamond,
/// yearly mythic. All-time has no crown - it never closes, so there is nothing to freeze.
///
/// `docs/champion-recognition.md` owns the product rules; this type only names them.
enum ChampionTitle: String, CaseIterable, Comparable, Sendable {
    case weekly
    case monthly
    case yearly

    init?(timeFrame: LeaderboardTimeFrame) {
        switch timeFrame {
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        case .daily, .allTime: return nil
        }
    }

    var timeFrame: LeaderboardTimeFrame {
        switch self {
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    /// Rarer titles lead: a climber holding the year and the week wears the mythic crown.
    var rarity: Int {
        switch self {
        case .weekly: 0
        case .monthly: 1
        case .yearly: 2
        }
    }

    static func < (lhs: ChampionTitle, rhs: ChampionTitle) -> Bool {
        lhs.rarity < rhs.rarity
    }

    /// The shipped `LeaderboardCrown` art, recoloured per title with the same silhouette.
    var crownAssetName: String {
        switch self {
        case .weekly: "LeaderboardCrown"
        case .monthly: "LeaderboardCrownDiamond"
        case .yearly: "LeaderboardCrownMythic"
        }
    }

    /// The title's label colour: the gold medal token, the diamond ice, the mythic violet.
    var tint: Color {
        switch self {
        case .weekly: Color.championGold
        case .monthly: Color.championDiamond
        case .yearly: Color.championMythic
        }
    }

    /// The soft glow drawn behind the crown so it separates from any picture.
    var glow: Color {
        switch self {
        case .weekly: Color.championGold
        case .monthly: Color.championDiamond
        case .yearly: Color(hex: "9B6BFF")
        }
    }

    /// First place's podium ring on the board that awards this title.
    var podiumRingColors: [Color] {
        switch self {
        case .weekly:
            [
                Color(red: 1.0, green: 0.93, blue: 0.46),
                Color(red: 0.96, green: 0.75, blue: 0.16),
                Color(red: 0.58, green: 0.39, blue: 0.04),
                Color(red: 1.0, green: 0.93, blue: 0.46)
            ]
        case .monthly:
            [Color(hex: "E6FBFF"), Color(hex: "58E3FF"), Color(hex: "1E82BF"), Color(hex: "E6FBFF")]
        case .yearly:
            Color.championMythicSpectrum
        }
    }
}

extension Color {
    /// The weekly title's gold is the core medal token, not a fourth gold.
    static var championGold: Color { .ascendMedalGold }

    /// The monthly title's diamond ice.
    static let championDiamond = Color(hex: "58E3FF")

    /// The yearly title's label violet, readable on black where the full mythic sweep is not.
    static let championMythic = Color(hex: "B184FF")

    /// The climb tier's mythic colours, swept around a ring.
    static let championMythicSpectrum: [Color] = [
        Color(hex: "6F52FF"),
        Color(hex: "B45DFF"),
        Color(hex: "FF7F33"),
        Color(hex: "F2C94C"),
        Color(hex: "9BE7B3"),
        Color(hex: "7091FF"),
        Color(hex: "6F52FF")
    ]
}
