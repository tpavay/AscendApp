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
struct WorkoutHeartRateRecoverySnapshotTests {
    @Test("Workout Detail says nothing about heart rate when the climb has none")
    func noHeartRateRendersNoSection() async throws {
        let previousAuthorizationState = HealthKitSyncState.hasRequestedAuthorization
        HealthKitSyncState.hasRequestedAuthorization = false
        defer { HealthKitSyncState.hasRequestedAuthorization = previousAuthorizationState }

        let workout = makeWorkout()
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

    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

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
        let container = try #require(Self.container, "The detail test needs an in-memory store")
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let host = UIHostingController(
            rootView: WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        )

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "The test host app should expose a live window scene"
        )
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            window.rootViewController = nil
            window.windowScene = nil
        }

        pump(window, for: 0.6)
        let scrollView = try #require(firstScrollView(in: window), "Workout Detail should scroll")
        let maximumOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let pageStride = max(scrollView.bounds.height * 0.7, 1)
        var offsets = Array(stride(from: CGFloat.zero, through: maximumOffset, by: pageStride))
        if offsets.last != maximumOffset {
            offsets.append(maximumOffset)
        }

        var recognizedPages: [String] = []
        for offset in offsets {
            scrollView.contentOffset = CGPoint(x: 0, y: offset)
            pump(window, for: 0.08)
            recognizedPages.append(try await recognizedText(in: screenshot(window)))
        }

        return recognizedPages.joined(separator: " ").lowercased()
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }

    private func pump(_ window: UIWindow, for duration: TimeInterval) {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
        window.layoutIfNeeded()
    }

    private func screenshot(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { context in
            if window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) == false {
                window.layer.render(in: context.cgContext)
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
