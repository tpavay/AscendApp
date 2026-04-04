import SwiftUI

enum ClimbTier: String, Codable, CaseIterable, Comparable {
    case common
    case bronze
    case silver
    case gold
    case diamond
    case epic
    case legendary
    case mythic

    var color: Color {
        switch self {
        case .common:
            return Color(hex: "AEB8C8")
        case .bronze:
            return Color(hex: "D99143")
        case .silver:
            return Color(hex: "E3E8F2")
        case .gold:
            return Color(hex: "F5C742")
        case .diamond:
            return Color(hex: "58E3FF")
        case .epic:
            return Color(hex: "B184FF")
        case .legendary:
            return Color(hex: "FF7A5C")
        case .mythic:
            return Color(hex: "D2F200")
        }
    }

    var displayName: String {
        rawValue.capitalized
    }

    private var sortRank: Int {
        switch self {
        case .common:
            return 0
        case .bronze:
            return 1
        case .silver:
            return 2
        case .gold:
            return 3
        case .diamond:
            return 4
        case .epic:
            return 5
        case .legendary:
            return 6
        case .mythic:
            return 7
        }
    }

    init(steps: Int) {
        switch steps {
        case ..<300:
            self = .common
        case 300..<600:
            self = .bronze
        case 600..<1_200:
            self = .silver
        case 1_200..<2_100:
            self = .gold
        case 2_100..<3_500:
            self = .diamond
        case 3_500..<6_000:
            self = .epic
        case 6_000..<12_000:
            self = .legendary
        default:
            self = .mythic
        }
    }

    static func < (lhs: ClimbTier, rhs: ClimbTier) -> Bool {
        lhs.sortRank < rhs.sortRank
    }
}
