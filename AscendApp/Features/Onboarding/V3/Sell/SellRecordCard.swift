import Foundation

/// One record card on 03: a best effort and where it stands. The titles, ordinals and numbers come
/// from the same types the Progress tab uses, so the card reads exactly as the climber's own will.
///
/// The values are examples of what the app keeps, not the climber's: nobody has climbed yet.
struct SellRecordCard: Equatable, Identifiable {
    enum Tier: Equatable {
        case gold
        case silver

        /// 1 for the all-time best, 2 for the runner-up.
        var rank: Int { self == .gold ? 1 : 2 }
    }

    let id: String
    let tier: Tier
    let metric: BestEffortMetric
    /// The effort's own number: "7,309 steps" or "40:08".
    let value: String
    let month: Int
    let day: Int

    /// "ALL-TIME BEST", then "2ND ALL-TIME".
    var kicker: String {
        switch tier {
        case .gold: SellScreenCopy.GetBetter.allTimeBest.uppercased()
        case .silver: "\(BestEffortFormatting.ordinal(tier.rank)) ALL-TIME".uppercased()
        }
    }

    var title: String { metric.title }

    /// "7,309 steps · Oct 3". Every card carries its number; the design's first card left it out.
    func detail(calendar: Calendar = .current) -> String {
        let date = calendar.date(from: DateComponents(year: 2_026, month: month, day: day)) ?? .now
        return "\(value) · \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var accessibilitySummary: String {
        "\(kicker.capitalized), \(title), \(detail())"
    }

    static let examples: [SellRecordCard] = [
        SellRecordCard(
            id: "gold-hour",
            tier: .gold,
            metric: .mostStepsInTime(minutes: 60),
            value: "\(BestEffortFormatting.integer(7_309)) steps",
            month: 10,
            day: 3
        ),
        SellRecordCard(
            id: "gold-3000",
            tier: .gold,
            metric: .fastestStepTarget(steps: 3_000),
            value: BestEffortFormatting.clockTime(40 * 60 + 8),
            month: 10,
            day: 5
        ),
        SellRecordCard(
            id: "silver-hour",
            tier: .silver,
            metric: .mostStepsInTime(minutes: 60),
            value: "\(BestEffortFormatting.integer(5_004)) steps",
            month: 10,
            day: 9
        ),
        SellRecordCard(
            id: "silver-2000",
            tier: .silver,
            metric: .fastestStepTarget(steps: 2_000),
            value: BestEffortFormatting.clockTime(24 * 60 + 33),
            month: 9,
            day: 29
        )
    ]
}
