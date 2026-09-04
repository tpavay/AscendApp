import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Window-hosted coverage for Workout Detail's show-or-hide heart-rate contract.
///
/// Each test mounts the shipping `WorkoutDetailView` through `RenderedScreen`, scrolls through
/// every viewport, and reads the copy a climber can actually see at each one off the
/// accessibility tree. A page is photographed only under `ASCEND_EVIDENCE_DIR`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct WorkoutDetailHeartRateVisibilityTests {
    @Test("Workout Detail says nothing about heart rate when the climb has none")
    func noHeartRateRendersNoSection() async throws {
        let previousAuthorizationState = HealthKitSyncState.hasRequestedAuthorization
        HealthKitSyncState.hasRequestedAuthorization = false
        defer { HealthKitSyncState.hasRequestedAuthorization = previousAuthorizationState }

        let workout = makeWorkout()

        // The fixture has to stay a climb enrichment is still considering. A foreign source, or
        // heart rate already attached, would make the absence assertions below pass for the
        // wrong reason and stop guarding anything.
        #expect(workout.isInAppSensorWorkout)
        #expect(workout.avgHeartRate == nil)
        #expect(workout.heartRateTimeSeries.isEmpty)

        let text = try await copyAcrossDetail(
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

        let text = try await copyAcrossDetail(
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

    /// Everything the detail screen publishes across every scroll position a climber can reach,
    /// lowercased and joined - the same walk the OCR pass made, read off the tree instead.
    private func copyAcrossDetail(
        _ workout: Workout,
        evidenceName: String
    ) async throws -> String {
        let container = try Self.makeRetainedContainer()
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let detail = WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
            .environment(AuthenticationViewModel())
            .environment(MediaUploadManager.shared)
            .modelContainer(container)

        return try await RenderedScreen.host(detail) { screen in
            let scrollView = try #require(
                Self.firstScrollView(in: screen.window),
                "The no-photo Workout Detail layout should render a ScrollView"
            )

            var pages: [String] = []
            for (index, offset) in Self.pageOffsets(of: scrollView).enumerated() {
                scrollView.contentOffset = CGPoint(x: 0, y: offset)
                try await screen.settle(.turns(2))
                pages.append(try await screen.copy())
                try screen.photograph(named: "\(evidenceName)-\(index + 1)")
            }

            return pages.joined(separator: " ")
        }
    }

    /// Every scroll offset a climber can reach, first page through last.
    private static func pageOffsets(of scrollView: UIScrollView) -> [CGFloat] {
        let maximumOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let pageStride = max(scrollView.bounds.height * 0.7, 1)
        var offsets = Array(stride(from: CGFloat.zero, through: maximumOffset, by: pageStride))
        if offsets.last != maximumOffset {
            offsets.append(maximumOffset)
        }

        return offsets
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }

        return nil
    }

    /// `WorkoutDetailView` carries a `@Query`, and SwiftUI keeps observing SwiftData for a beat
    /// after the host is torn down. A container that dies with the test is gone before that
    /// observer is, and the observer then traps on the dangling reference the next time *any*
    /// suite calls `ModelContext.save()`. Each run still gets its own store, so no suite renders
    /// against another's fixtures - the same arrangement `HostedWorkoutDetailScreen` keeps.
    private static var retainedContainers: [ModelContainer] = []

    private static func makeRetainedContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retainedContainers.append(container)
        return container
    }
}
