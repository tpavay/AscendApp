import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision

@testable import AscendApp

/// Window-hosted coverage for Workout Detail's show-or-hide heart-rate contract.
///
/// Each test mounts the shipping `WorkoutDetailView`, scrolls through every viewport, and OCRs
/// what a climber can actually see.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct WorkoutDetailHeartRateVisibilityTests {
    @Test("Workout Detail says nothing about heart rate when the climb has none")
    func noHeartRateRendersNoSection() async throws {
        let previousAuthorizationState = HealthKitSyncState.hasRequestedAuthorization
        HealthKitSyncState.hasRequestedAuthorization = false
        defer { HealthKitSyncState.hasRequestedAuthorization = previousAuthorizationState }

        let workout = makeWorkout()

        #expect(
            AppleHealthEnrichmentService.shared.phase(for: workout) != .notApplicable,
            """
            The fixture has to stay a climb enrichment is still considering. Once it reads as \
            notApplicable - a foreign source, or heart rate already attached - the absence \
            assertions below pass for the wrong reason and stop guarding anything.
            """
        )

        let text = try await recognizedTextAcrossDetail(
            workout,
            evidenceName: "workout-detail-without-heart-rate"
        )

        #expect(text.contains("heart rate") == false)
        #expect(text.contains("connect apple health") == false)
        #expect(text.contains("checking apple health") == false)
        #expect(text.contains("waiting on your wearable") == false)
    }

    @Test("Workout Detail still renders the heart-rate chart when samples exist")
    func heartRateSamplesRenderTheChart() async throws {
        let workout = makeWorkout()
        let samples = (0..<24).map { index in
            HeartRateDataPoint(
                timestamp: workout.date.addingTimeInterval(Double(index) * 45),
                heartRate: 128 + index
            )
        }
        workout.heartRateData = samples.encoded
        workout.avgHeartRate = 139
        workout.maxHeartRate = 151

        let text = try await recognizedTextAcrossDetail(
            workout,
            evidenceName: "workout-detail-with-heart-rate"
        )

        #expect(text.contains("heart rate"))
        #expect(text.contains("avg"))
        #expect(text.contains("max"))
        #expect(text.contains("connect apple health") == false)
    }

    private func makeWorkout() -> Workout {
        Workout(
            name: "CN Tower Live Climb",
            date: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 1_908,
            steps: 2_579,
            floors: 144,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
    }

    private func recognizedTextAcrossDetail(
        _ workout: Workout,
        evidenceName: String
    ) async throws -> String {
        try await HostedWorkoutDetailScreen.run(for: workout) { screen in
            var recognizedPages: [String] = []
            var pages: [UIImage] = []
            for offset in screen.pageOffsets {
                screen.scroll(to: offset)
                screen.settle(for: 0.08)
                let shot = screen.screenshot()
                pages.append(shot)
                recognizedPages.append(try await recognizedText(in: shot))
            }

            writeEvidence(pages: pages, named: evidenceName)

            return recognizedPages.joined(separator: " ").lowercased()
        }
    }

    /// Saves what the OCR above actually read, so a reviewer can see the screen rather than
    /// take the assertions' word for it.
    private func writeEvidence(pages: [UIImage], named name: String) {
        guard let strip = horizontalStrip(of: pages), let png = strip.pngData() else { return }

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try? png.write(to: url)
        print("Rendered Workout Detail evidence: \(url.path())")
    }

    private func horizontalStrip(of pages: [UIImage]) -> UIImage? {
        guard let first = pages.first else { return nil }

        let gutter: CGFloat = 16
        let size = CGSize(
            width: first.size.width * CGFloat(pages.count) + gutter * CGFloat(pages.count - 1),
            height: first.size.height
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, page) in pages.enumerated() {
                page.draw(
                    at: CGPoint(x: (first.size.width + gutter) * CGFloat(index), y: 0)
                )
            }
        }
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "The screenshot should have a CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        return try await request.perform(on: cgImage)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}
