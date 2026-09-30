import Foundation

/// The comparison's HEART RATE rows, and which of them to draw.
///
/// A row is drawn when at least one side holds that number, the same rule the achievement rows
/// follow: `142 bpm | -` is worth showing, a row where nobody has heart rate is a row about
/// nothing. A climber with no heart rate reads `-`, the way an undeclared age or weight already
/// does in PROFILE. While the other climber is still loading, a row is kept only for a number
/// the viewer holds, so the section never pops in empty and never flashes rows that vanish.
struct ProfileHeartRateComparison: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case average
        case max

        var id: String { rawValue }

        var label: String {
            switch self {
            case .average:
                return "Avg heart rate"
            case .max:
                return "Max heart rate"
            }
        }
    }

    struct Row: Equatable, Identifiable {
        let kind: Kind
        let viewerBpm: Int?
        let otherBpm: Int?

        var id: String { kind.id }
    }

    let rows: [Row]

    init(
        viewer: ProfileHeartRateSummary?,
        other: ProfileHeartRateSummary?,
        isOtherLoading: Bool
    ) {
        rows = Kind.allCases.compactMap { kind in
            let viewerBpm = Self.bpm(kind, in: viewer)
            let otherBpm = isOtherLoading ? nil : Self.bpm(kind, in: other)
            guard viewerBpm != nil || otherBpm != nil else { return nil }
            return Row(kind: kind, viewerBpm: viewerBpm, otherBpm: otherBpm)
        }
    }

    var isEmpty: Bool {
        rows.isEmpty
    }

    static func text(for bpm: Int?) -> String {
        bpm.map { "\($0) bpm" } ?? "-"
    }

    private static func bpm(_ kind: Kind, in summary: ProfileHeartRateSummary?) -> Int? {
        switch kind {
        case .average:
            return summary?.averageBpm
        case .max:
            return summary?.maxBpm
        }
    }
}
