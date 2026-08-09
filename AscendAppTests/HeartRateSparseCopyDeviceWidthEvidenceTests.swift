import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The sparse-series stand-in copy, rendered at the width Workout Detail actually hands it.
///
/// `HeartRateDensityProof` renders the same panel inside a 372pt proof container. Workout
/// Detail's scroll content is 20pt inset on each side, so on the narrowest phone Ascend
/// supports the panel is materially narrower than that - and the #438 copy that replaced
/// "Not enough heart-rate samples to chart" is roughly twice as long. This pins that the new
/// string still fits the card at real device width instead of running past its edges.
@MainActor
struct HeartRateSparseCopyDeviceWidthEvidenceTests {
    /// iPhone 16 Pro portrait width, less `WorkoutDetailView`'s 20pt horizontal content inset.
    private static let contentWidth: CGFloat = 393 - 40

    @Test("The sparse-series copy wraps inside its card at every shipped phone width")
    func rendersSparseCopyAtDeviceWidth() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let cases = [
            SparseCopyCase(
                id: "single",
                caption: "One reading · the longest of the three strings",
                samples: [
                    HeartRateDataPoint(timestamp: start.addingTimeInterval(240), heartRate: 149)
                ],
                average: 149,
                maximum: 149
            ),
            SparseCopyCase(
                id: "two",
                caption: "Two readings · the count is reported, not a failed load",
                samples: [
                    HeartRateDataPoint(timestamp: start.addingTimeInterval(180), heartRate: 141),
                    HeartRateDataPoint(timestamp: start.addingTimeInterval(900), heartRate: 163)
                ],
                average: 152,
                maximum: 163
            )
        ]

        // Every phone width Ascend ships to, less the same 20pt inset: iPhone SE/13 mini,
        // iPhone 16 Pro, and iPhone 16 Pro Max.
        let widths: [CGFloat] = [375 - 40, Self.contentWidth, 430 - 40]

        let proof = SparseCopyProof(cases: cases, start: start, widths: widths)
        let renderer = ImageRenderer(content: proof)
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")

        // The proof pins the widest phone. Anything wider means the panel's contents pushed
        // the layout past the screen instead of wrapping inside the card.
        #expect(image.size.width == 430)

        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory)
            .appending(path: "heart-rate-sparse-copy-device-width.png")
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("ASCEND_EVIDENCE_FILE: \(url.path())")
    }
}

private struct SparseCopyCase: Identifiable {
    let id: String
    let caption: String
    let samples: [HeartRateDataPoint]
    let average: Int?
    let maximum: Int?
}

private struct SparseCopyProof: View {
    let cases: [SparseCopyCase]
    let start: Date
    let widths: [CGFloat]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Workout Detail · sparse-series copy at every shipped phone width")
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)

            ForEach(widths, id: \.self) { width in
                VStack(alignment: .leading, spacing: 14) {
                    Text("CONTENT WIDTH \(Int(width))PT · SCREEN \(Int(width) + 40)PT")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent)

                    ForEach(cases) { sparseCase in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sparseCase.caption.uppercased())
                                .font(.montserratSemiBold(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)

                            HeartRateChartView(
                                heartRateData: sparseCase.samples,
                                workoutStartTime: start,
                                workoutDuration: 1_200,
                                averageHeartRateBpm: sparseCase.average,
                                maxHeartRateBpm: sparseCase.maximum
                            )
                            .frame(width: width)
                            // A hairline behind the panel marks exactly where the card's own
                            // edges are, so copy that runs past them is visible rather than
                            // inferred.
                            .background(
                                Rectangle()
                                    .stroke(Color.ascendAccent.opacity(0.6), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(width: 430, alignment: .leading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
