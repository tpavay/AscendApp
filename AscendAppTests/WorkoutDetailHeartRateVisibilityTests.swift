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

        let text = try await recognizedTextAcrossDetail(workout)

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

        let text = try await recognizedTextAcrossDetail(workout)

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

    private func recognizedTextAcrossDetail(_ workout: Workout) async throws -> String {
        try await HostedWorkoutDetailScreen.run(for: workout) { screen in
            var recognizedPages: [String] = []
            for offset in screen.pageOffsets {
                screen.scroll(to: offset)
                screen.settle(for: 0.08)
                recognizedPages.append(try await recognizedText(in: screen.screenshot()))
            }

            return recognizedPages.joined(separator: " ").lowercased()
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
