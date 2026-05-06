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
            return Color(hex: "8FAE9C")
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
            return Color(hex: "9B6BFF")
        }
    }

    var glowColor: Color {
        switch self {
        case .mythic:
            return Color(hex: "7A4DFF").opacity(0.28)
        default:
            return color.opacity(0.18)
        }
    }

    var borderColors: [Color] {
        switch self {
        case .mythic:
            return [
                Color(hex: "6F52FF"),
                Color(hex: "B45DFF"),
                Color(hex: "FF7F33"),
                Color(hex: "F2C94C"),
                Color(hex: "9BE7B3"),
                Color(hex: "7091FF"),
                Color(hex: "6F52FF")
            ]
        default:
            return [
                color.lighter(by: 0.12),
                color,
                color.darker(by: 0.12),
                color,
                color.lighter(by: 0.08)
            ]
        }
    }

    var shadowColor: Color {
        switch self {
        case .mythic:
            return Color(hex: "7A4DFF")
        default:
            return color
        }
    }

    var detailStripStyle: AnyShapeStyle {
        switch self {
        case .mythic:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "644CE6"),
                        Color(hex: "9D62FF"),
                        Color(hex: "F09032")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        default:
            return AnyShapeStyle(color.opacity(0.82))
        }
    }

    var usesEmphasizedBorderStyle: Bool {
        self == .mythic
    }

    var displayName: String {
        rawValue.capitalized
    }

    var stepRangeDescription: String {
        switch self {
        case .common:
            return "Under 300 steps"
        case .bronze:
            return "300-599 steps"
        case .silver:
            return "600-1,199 steps"
        case .gold:
            return "1,200-2,099 steps"
        case .diamond:
            return "2,100-3,499 steps"
        case .epic:
            return "3,500-5,999 steps"
        case .legendary:
            return "6,000-11,999 steps"
        case .mythic:
            return "12,000+ steps"
        }
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
