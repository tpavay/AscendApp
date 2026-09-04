import SwiftUI
import Testing
@testable import AscendApp

@MainActor
struct HeartRateChartDropoutSnapshotTests {
    @Test("Saved heart-rate chart leaves a visible gap where the strap dropped")
    func rendersDropoutGap() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        // The chart draws one line per segment, so the series splitting in two is the gap:
        // the data set the shipping view builds says so before any pixel does. The 3x
        // photograph is written only under `ASCEND_EVIDENCE_DIR`.
        let dataSet = HeartRateChartDataSet(
            samples: samples(start: start),
            workoutStartTime: start,
            workoutDuration: 420
        )
        #expect(dataSet.segments.count == 2)

        try RenderedScreen.photograph(chartProof(start: start), named: "heart-rate-chart-dropout")
    }

    /// 0-120s captured, 120-300s strap silent, 300-420s captured again.
    private func samples(start: Date) -> [HeartRateDataPoint] {
        var points: [HeartRateDataPoint] = []
        for second in stride(from: 0, through: 120, by: 5) {
            points.append(
                HeartRateDataPoint(
                    timestamp: start.addingTimeInterval(TimeInterval(second)),
                    heartRate: 112 + Int((Double(second) / 12).rounded())
                )
            )
        }
        for second in stride(from: 300, through: 420, by: 5) {
            points.append(
                HeartRateDataPoint(
                    timestamp: start.addingTimeInterval(TimeInterval(second)),
                    heartRate: 154 - Int((Double(second - 300) / 10).rounded())
                )
            )
        }
        return points
    }

    private func chartProof(start: Date) -> some View {
        HeartRateChartView(
            heartRateData: samples(start: start),
            workoutStartTime: start,
            workoutDuration: 420,
            averageHeartRateBpm: 133,
            maxHeartRateBpm: 154
        )
        .padding(20)
        .frame(width: 390)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
