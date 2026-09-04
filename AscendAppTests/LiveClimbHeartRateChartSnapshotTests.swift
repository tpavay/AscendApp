import Foundation
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Evidence that a populated heart-rate trace still renders at every supported density: the data
/// set behind the chart keeps every reading at each density, and the proof sheet is photographed
/// when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
struct LiveClimbHeartRateChartSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func rendersEveryPopulatedHeartRateDensitySensibly() throws {
        let start = now.addingTimeInterval(-(20 * 60))
        let duration: TimeInterval = 20 * 60

        func samples(_ bpms: [(TimeInterval, Int)]) -> [HeartRateDataPoint] {
            bpms.map {
                HeartRateDataPoint(
                    timestamp: start.addingTimeInterval($0.0),
                    heartRate: $0.1
                )
            }
        }

        let dense: [HeartRateDataPoint] = (0..<40).map { index in
            let offset = Double(index) * 30
            let wave = Int(20 * sin(Double(index) / 4))
            let drift = index / 6
            return HeartRateDataPoint(
                timestamp: start.addingTimeInterval(offset),
                heartRate: 128 + wave + drift
            )
        }

        let densities = [
            HeartRateDensityCase(
                id: "single",
                caption: "One reading · avg and max are still real, so they stay",
                samples: samples([(600, 149)]),
                average: 149,
                maximum: 149,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "two",
                caption: "Two readings · the count is reported, not a failed load",
                samples: samples([(240, 141), (900, 163)]),
                average: 152,
                maximum: 163,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "sparse",
                caption: "Five readings · charts with isolated points, no fake curve",
                samples: samples([(0, 118), (300, 144), (660, 159), (1_020, 166), (1_180, 138)]),
                average: 145,
                maximum: 166,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "dense",
                caption: "Dense sample cadence · the full trace",
                samples: dense,
                average: 141,
                maximum: 172,
                duration: duration,
                start: start
            ),
        ]

        #expect(
            HeartRateChartView.unavailableChartMessage(sampleCount: 2)
                == "Your wearable logged 2 readings for this climb - too few to chart"
        )

        // None of these densities reaches the thinning budget, so every reading the wearable
        // logged is a mark the chart plots.
        for density in densities {
            let dataSet = HeartRateChartDataSet(
                samples: density.samples,
                workoutStartTime: density.start,
                workoutDuration: density.duration
            )
            #expect(
                dataSet.points.count == density.samples.count,
                "\(density.id): \(density.samples.count) readings became \(dataSet.points.count) marks"
            )
        }

        if RenderedScreen.isPhotographing {
            try RenderedScreen.photograph(
                HeartRateDensityProof(cases: densities),
                named: "heart-rate-series-densities"
            )
        }
    }
}

private struct HeartRateDensityCase: Identifiable {
    let id: String
    let caption: String
    let samples: [HeartRateDataPoint]
    let average: Int?
    let maximum: Int?
    let duration: TimeInterval
    let start: Date
}

private struct HeartRateDensityProof: View {
    let cases: [HeartRateDensityCase]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Workout Detail · populated heart-rate series")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            ForEach(cases) { density in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(density.id.uppercased()) · \(density.caption)")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    HeartRateChartView(
                        heartRateData: density.samples,
                        workoutStartTime: density.start,
                        workoutDuration: density.duration,
                        averageHeartRateBpm: density.average,
                        maxHeartRateBpm: density.maximum
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
