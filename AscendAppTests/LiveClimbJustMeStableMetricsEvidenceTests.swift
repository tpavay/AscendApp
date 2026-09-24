import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// The Just Me landmark layouts, read off the real `LiveClimbSessionView` mid-recording: the stats
/// hold one size and one place however many digits they carry, and CURRENT SPM stays a
/// placeholder through the first thirty seconds while AVG SPM reads from the start.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustMeStableMetricsEvidenceTests {
    struct Fixture: Sendable, CustomTestStringConvertible {
        let id: String
        let name: String
        let city: String
        let country: String
        let realStairCount: Int
        var testDescription: String { id }
    }

    nonisolated static let landmarks: [Fixture] = [
        Fixture(id: "empire-state-building", name: "Empire State Building", city: "New York", country: "United States", realStairCount: 1_576),
        Fixture(id: "eiffel-tower", name: "Eiffel Tower", city: "Paris", country: "France", realStairCount: 1_665),
        Fixture(id: "charminar", name: "Charminar", city: "Hyderabad", country: "India", realStairCount: 149),
    ]

    /// Clock and step pairs whose readings cross digit counts: SPM 7, 74, 148 and 148, over steps
    /// of 7, 37, 74 and 148. Each window spans the session's opening sample, so CURRENT and AVG
    /// agree and both reach three digits.
    private static let states: [(duration: TimeInterval, steps: Int, spm: Int)] = [
        (60, 7, 7),
        (30, 37, 74),
        (30, 74, 148),
        (60, 148, 148),
    ]

    @Test("Every stat keeps one frame as its reading goes from one digit to three", arguments: landmarks)
    func statsHoldTheirFrameAcrossDigitCounts(fixture: Fixture) async throws {
        let size = try Self.deviceScreenSize()
        var framesByState: [[String: CGRect]] = []

        for state in Self.states {
            try await Self.hostSession(fixture: fixture, steps: state.steps, duration: state.duration, size: size) { screen, viewModel in
                #expect(viewModel.currentStepsPerMinute == state.spm)
                #expect(viewModel.averageStepsPerMinute == state.spm)

                let texts = try await screen.texts { texts in
                    texts.contains { $0.text.contains("ELAPSED") } && texts.contains { $0.text.contains("AVG") }
                }
                var frames: [String: CGRect] = [:]
                frames["steps"] = texts.first { $0.text.contains("of \(fixture.realStairCount.formatted()) steps") }?.frame
                frames["elapsed"] = texts.first { $0.text.contains("ELAPSED") }?.frame
                frames["rank"] = texts.first { $0.text.contains("CURRENT RANK") }?.frame
                frames["current SPM"] = texts.first { $0.text.contains("CURRENT") && $0.text.contains("SPM") }?.frame
                frames["avg SPM"] = texts.first { $0.text.contains("AVG") && $0.text.contains("SPM") }?.frame
                for (name, frame) in frames.sorted(by: { $0.key < $1.key }) {
                    print("STABLE-METRIC \(fixture.id) \(Int(size.width))pt spm=\(state.spm) steps=\(state.steps) \(name) \(frame.integral)")
                }
                #expect(frames.count == 5, "every stat is on screen: \(texts.map(\.text))")
                framesByState.append(frames)

                try screen.photograph(named: "stable-metrics-\(fixture.id)-spm\(String(format: "%03d", state.spm))-steps\(String(format: "%03d", state.steps))-\(Int(size.width))pt")
            }
        }

        // A stat's element hugs its text, so its width naturally follows the digit count of a
        // left-aligned reading. What must not move is its origin, and what must not change is its
        // height - the line height its font size sets.
        let reference = try #require(framesByState.first)
        for (index, frames) in framesByState.enumerated().dropFirst() {
            for (name, frame) in reference {
                let other = try #require(frames[name], "\(name) missing in state \(index)")
                #expect(
                    abs(other.minX - frame.minX) < 0.5 && abs(other.minY - frame.minY) < 0.5,
                    "\(fixture.id): \(name) moved between SPM \(Self.states[0].spm) and \(Self.states[index].spm): \(frame.integral) vs \(other.integral)"
                )
                #expect(
                    abs(other.height - frame.height) < 0.5,
                    "\(fixture.id): \(name) resized between SPM \(Self.states[0].spm) and \(Self.states[index].spm): \(frame.integral) vs \(other.integral)"
                )
            }
        }
    }

    @Test("In the first thirty seconds AVG SPM reads a number and CURRENT SPM its placeholder", arguments: landmarks)
    func firstThirtySeconds(fixture: Fixture) async throws {
        let size = try Self.deviceScreenSize()
        try await Self.hostSession(fixture: fixture, steps: 16, duration: 12, size: size) { screen, viewModel in
            #expect(viewModel.currentPaceDisplay == "—")
            #expect(viewModel.averagePaceDisplay == "80")

            let texts = try await screen.texts { texts in texts.contains { $0.text.contains("AVG") } }
            let current = try #require(texts.first { $0.text.contains("CURRENT") && $0.text.contains("SPM") })
            let average = try #require(texts.first { $0.text.contains("AVG") && $0.text.contains("SPM") })
            #expect(current.text.contains("—"), "CURRENT reads its placeholder: \(current.text)")
            #expect(average.text.contains("80"), "AVG reads the climb-so-far pace: \(average.text)")

            try screen.photograph(named: "photo-progress-\(fixture.id)-first-30-seconds-\(Int(size.width))pt")
        }
    }

    // MARK: - Hosting

    private static func hostSession(
        fixture: Fixture,
        steps: Int,
        duration: TimeInterval,
        size: CGSize,
        _ body: @MainActor (HostedScreen, LiveClimbSessionViewModel) async throws -> Void
    ) async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let climb = try #require(BundledClimbCatalog.climbs.first { $0.id == fixture.id })
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateMonitor: HeartRateMonitorService(
                userDefaults: UserDefaults(suiteName: "LiveClimbJustMeStableMetricsEvidenceTests.\(UUID().uuidString)")!
            ),
            progressImageRepository: FixtureClimbProgressImageRepository()
        )
        viewModel.start(modelContext: container.mainContext)
        await viewModel.loadProgressArtworkIfNeeded()
        #expect(viewModel.progressArtwork != nil, "\(fixture.id)'s cut-out loaded from its fixture")
        motionSession.stepCount = steps
        motionSession.duration = duration

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            try await body(screen, viewModel)
        }
    }

    private static func deviceScreenSize() throws -> CGSize {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return scene.screen.bounds.size
    }
}
