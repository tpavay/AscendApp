import Foundation

/// Every sticker the share sheet can offer, in the order the grid shows them.
enum StickerKind: String, CaseIterable, Identifiable, Sendable {
    // This climb
    case stack, strip, list, line, personalRecord, heartRate, ticket, pace
    case splitsChart, fastestSplit, climbBellCurve, climbRank

    // Totals
    case calendar, weeklySteps, averagePace, stepsAndTime, floorsAndTime, floors
    case climbsAndDots, stepsAndClimbs
    case weeklyRank, monthlyRank, yearlyRank, rankTrio
    case weeklyBellCurve, monthlyBellCurve, yearlyBellCurve

    var id: String { rawValue }

    var isTotals: Bool {
        switch self {
        case .stack, .strip, .list, .line, .personalRecord, .heartRate, .ticket, .pace,
             .splitsChart, .fastestSplit, .climbBellCurve, .climbRank:
            return false
        case .calendar, .weeklySteps, .averagePace, .stepsAndTime, .floorsAndTime, .floors,
             .climbsAndDots, .stepsAndClimbs, .weeklyRank, .monthlyRank, .yearlyRank, .rankTrio,
             .weeklyBellCurve, .monthlyBellCurve, .yearlyBellCurve:
            return true
        }
    }

    /// The short name VoiceOver reads for the tile.
    var title: String {
        switch self {
        case .stack: return "Stack"
        case .strip: return "Strip"
        case .list: return "List"
        case .line: return "Line"
        case .personalRecord: return "PR ring"
        case .heartRate: return "Heart rate"
        case .ticket: return "Ticket"
        case .pace: return "Pace"
        case .splitsChart: return "Splits chart"
        case .fastestSplit: return "Fastest split"
        case .climbBellCurve: return "Bell curve"
        case .climbRank: return "Rank"
        case .calendar: return "Monthly calendar"
        case .weeklySteps: return "Weekly steps chart"
        case .averagePace: return "Average pace"
        case .stepsAndTime: return "Steps and time"
        case .floorsAndTime: return "Floors and time"
        case .floors: return "Floors"
        case .climbsAndDots: return "Climb count"
        case .stepsAndClimbs: return "Steps and climbs"
        case .weeklyRank: return "Weekly rank"
        case .monthlyRank: return "Monthly rank"
        case .yearlyRank: return "Yearly rank"
        case .rankTrio: return "Week, month and year rank"
        case .weeklyBellCurve: return "Weekly bell curve"
        case .monthlyBellCurve: return "Monthly bell curve"
        case .yearlyBellCurve: return "Yearly bell curve"
        }
    }

    var accessibilityLabel: String {
        "\(title) sticker. Tap to copy, hold to save"
    }
}
