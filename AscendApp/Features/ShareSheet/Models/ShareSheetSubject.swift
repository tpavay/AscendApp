import Foundation

/// Everything a share card or sticker may say about one climb, resolved to display text once.
///
/// Pure value type: the card layouts, the stickers and the plain share text all read this and
/// never reach back into `Workout`, so what a card claims is decided in one place and is
/// unit-testable without a view tree.
struct ShareSheetSubject: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case justClimb
        case routine
        case landmark
    }

    /// Where a finish ranked, frozen at the moment the climb ended. Never recomputed here.
    struct Rank: Equatable, Sendable {
        let position: Int
        let field: Int

        init?(position: Int?, field: Int?) {
            guard let position, let field, position > 0, field > 0 else { return nil }
            self.position = min(position, field)
            self.field = field
        }

        var positionText: String { "\(position)" }
        var fieldText: String { field.formatted(.number.grouping(.automatic)) }

        /// `TOP 11%` for 7 of 64: the share of the field at or above this finish, never under 1.
        var topPercent: Int {
            max(1, Int((Double(position) / Double(field) * 100).rounded()))
        }

        /// `BEAT 89%` for 7 of 64: the share of the field behind this finish. Last place beat nobody.
        var beatPercent: Int {
            let beaten = Double(field - position) / Double(field)
            return min(max(Int((beaten * 100).rounded(.down)), 0), 99)
        }

        var isFirstAscent: Bool { field == 1 }
    }

    struct Split: Equatable, Sendable, Identifiable {
        let index: Int
        let durationSeconds: Int
        let steps: Int
        let stepsPerMinute: Double
        var id: Int { index }

        var number: String { "\(index + 1)" }
        var durationText: String { ShareSheetFormat.clock(durationSeconds) }
        var stepsText: String { steps.formatted(.number.grouping(.automatic)) }
        var stepsPerMinuteText: String { Int(stepsPerMinute.rounded()).formatted() }
    }

    /// One record the climb holds: the climber's own top three for a measure.
    struct BestEffort: Equatable, Sendable, Identifiable {
        /// The measure's id, so one measure counts once however many scopes it is a record in.
        let id: String
        let rankText: String
        let scopeText: String
        let title: String
        /// Lower is better; used only to keep the best ranking when a measure appears twice.
        let rank: Int

        var detailText: String { "\(rankText) \(scopeText)" }
    }

    let kind: Kind
    /// `Just Climb`, the routine's name, or the landmark's name.
    let title: String
    /// The card's small caps label: `JUST CLIMB`, `PYRAMID INTERVALS`, `SHANGHAI TOWER · 632 M`.
    let label: String
    /// `OCT 9`.
    let dateText: String
    let stepsText: String
    let durationText: String
    let stepsPerMinuteText: String
    let floorsText: String?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    /// The heart-rate series reduced to a small number of points for the sticker's trace.
    let heartRateTrace: [Double]
    let rank: Rank?
    let splits: [Split]
    let bestEfforts: [BestEffort]
    let landmark: Landmark?

    struct Landmark: Equatable, Sendable {
        let name: String
        let heightText: String
    }

    /// `1:02:50 · 5,004 steps · 79.6 SPM`, the sheet's headline.
    var headline: String {
        "\(durationText) · \(stepsText) steps · \(stepsPerMinuteText) SPM"
    }

    var hasSplits: Bool { splits.count >= 2 }
    var hasHeartRate: Bool { averageHeartRate != nil }
    var hasRank: Bool { rank != nil }

    var fastestSplit: Split? {
        splits.max { $0.stepsPerMinute < $1.stepsPerMinute }
    }
}
