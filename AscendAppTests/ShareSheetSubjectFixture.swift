import Foundation
@testable import AscendApp

/// A fully populated Just Climb subject for the share sheet tests. Values are the approved
/// mockup's sample numbers, so a rendered card can be compared against the design.
extension ShareSheetSubject {
    static func fixture(
        kind: Kind = .justClimb,
        floorsText: String? = "313",
        averageHeartRate: Int? = 127,
        heartRateTrace: [Double] = [120, 124, 130, 127, 133, 138, 144],
        rank: Rank? = Rank(position: 7, field: 64),
        splits: [Split] = ShareSheetSubject.sampleSplits,
        bestEfforts: [BestEffort] = [],
        landmark: Landmark? = nil
    ) -> ShareSheetSubject {
        ShareSheetSubject(
            kind: kind,
            title: kind == .landmark ? "Shanghai Tower" : "Just Climb",
            label: kind == .landmark ? "SHANGHAI TOWER · 632 M" : "JUST CLIMB",
            dateText: "OCT 9",
            stepsText: "5,004",
            durationText: "1:02:50",
            stepsPerMinuteText: "79.6",
            floorsText: floorsText,
            averageHeartRate: averageHeartRate,
            maxHeartRate: averageHeartRate == nil ? nil : 144,
            heartRateTrace: averageHeartRate == nil ? [] : heartRateTrace,
            rank: rank,
            splits: splits,
            bestEfforts: bestEfforts,
            landmark: landmark
        )
    }

    static let sampleSplits: [Split] = [
        Split(index: 0, durationSeconds: 540, steps: 648, stepsPerMinute: 72),
        Split(index: 1, durationSeconds: 540, steps: 684, stepsPerMinute: 76),
        Split(index: 2, durationSeconds: 540, steps: 711, stepsPerMinute: 79),
        Split(index: 3, durationSeconds: 540, steps: 729, stepsPerMinute: 81),
        Split(index: 4, durationSeconds: 540, steps: 747, stepsPerMinute: 83),
        Split(index: 5, durationSeconds: 540, steps: 738, stepsPerMinute: 82),
        Split(index: 6, durationSeconds: 530, steps: 747, stepsPerMinute: 85)
    ]

    static func effort(_ id: String, rank: Int = 1, scope: String = "ALL-TIME", title: String? = nil) -> BestEffort {
        BestEffort(
            id: id,
            rankText: ["1ST", "2ND", "3RD"][rank - 1],
            scopeText: scope,
            title: title ?? id.uppercased(),
            rank: rank
        )
    }
}
