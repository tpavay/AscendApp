import Foundation

/// The five answers to "How long is a usual climb?". Each stores the steps and minutes the rest of
/// the flow reads as the climber's usual climb, so the neutral version of the monthly event screen
/// can say what a climb looks like for them.
enum UsualClimbChoice: String, CaseIterable, Identifiable, Sendable {
    case newToThis = "new_to_this"
    case underFifteen = "under_15"
    case fifteenToThirty = "15_to_30"
    case thirtyToFortyFive = "30_to_45"
    case fortyFiveOrMore = "45_plus"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newToThis: "I'm new to this"
        case .underFifteen: "Under 15 min"
        case .fifteenToThirty: "15 to 30 min"
        case .thirtyToFortyFive: "30 to 45 min"
        case .fortyFiveOrMore: "45 min or more"
        }
    }

    var detail: String {
        switch self {
        case .newToThis: "We'll start easy"
        case .underFifteen: "~1,000 steps"
        case .fifteenToThirty: "~1,800 steps"
        case .thirtyToFortyFive: "~3,000 steps"
        case .fortyFiveOrMore: "~4,500 steps"
        }
    }

    /// What the answer stores. Minutes are a typical climb inside the band, at about the pace the
    /// steps imply.
    var steps: Int {
        switch self {
        case .newToThis, .underFifteen: 1_000
        case .fifteenToThirty: 1_800
        case .thirtyToFortyFive: 3_000
        case .fortyFiveOrMore: 4_500
        }
    }

    var minutes: Int {
        switch self {
        case .newToThis: 12
        case .underFifteen: 13
        case .fifteenToThirty: 22
        case .thirtyToFortyFive: 38
        case .fortyFiveOrMore: 55
        }
    }

    /// The choice an earlier visit stored, so back returns to the row the climber tapped. Both
    /// numbers have to match, and no two rows store the same pair, so a Health history's numbers
    /// that a later screen wrote never light a row.
    static func stored(steps: Int?, minutes: Int?) -> UsualClimbChoice? {
        guard let steps, let minutes else { return nil }
        return allCases.first { $0.steps == steps && $0.minutes == minutes }
    }
}
