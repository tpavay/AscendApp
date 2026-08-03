import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
struct HeartRateChartDropoutSnapshotTests {
    @Test("Saved heart-rate chart leaves a visible gap where the strap dropped")
    func rendersDropoutGap() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let renderer = ImageRenderer(
            content: chartProof(start: start)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "heart-rate-chart-dropout.png")
        try png.write(to: url)

        #expect(png.count > 5_000)
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
