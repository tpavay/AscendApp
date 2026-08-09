import Foundation
import HealthKit
import SwiftData
import Testing
@testable import AscendApp

/// A readable transcript of what enrichment actually does to a climb over the whole retry
/// curve, written to disk so the behaviour can be reviewed as a sequence rather than inferred
/// from a pile of assertions.
///
/// The case it walks is the one that made enrichment inert in the field (#438): a wearable
/// that publishes long after Ascend first looked. A Garmin-style companion-app sync is used
/// deliberately - an Apple Watch would have landed on the very first attempt and proved
/// nothing about the timing.
@MainActor
struct AppleHealthEnrichmentTimelineEvidenceTests {
    @Test("The retry curve attaches a late-published series, then stops on its own")
    func writesATranscriptOfTheWholeRetryCurve() async throws {
        let clock = TimelineClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let schedule = AppleHealthEnrichmentSchedule.standard
        let modelContext = try AscendLocalStoreFixture.makeModelContext()
        let store = AppleHealthEnrichmentAttemptStore(
            defaults: UserDefaults(suiteName: "timeline-\(UUID().uuidString)")!,
            schedule: schedule
        )

        let climbStart = clock.now.addingTimeInterval(-1_200)
        let workout = Workout(
            name: "Live Climb",
            date: climbStart,
            duration: 1_200,
            steps: 1_600,
            floors: Workout.stepsToFloors(1_600, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        modelContext.insert(workout)
        try modelContext.save()

        let reader = TimelineMetricsReader()
        let service = AppleHealthEnrichmentService(
            authorizationController: TimelineAuthorizationController(),
            metricsReader: reader,
            attemptStore: store,
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            now: { clock.now }
        )

        // The wearable's companion app syncs 23 minutes after the climb - after five reads
        // have already come back empty.
        let publishesAfter: TimeInterval = 23 * 60
        var lines: [String] = []
        let start = clock.now

        func stamp(_ elapsed: TimeInterval) -> String {
            formatted(elapsed).padding(toLength: 9, withPad: " ", startingAt: 0)
        }

        func record(_ label: String) {
            let elapsed = stamp(clock.now.timeIntervalSince(start))
            let reads = "reads: \(reader.requestedWindows.count)"
            let phase = describe(service.phase(for: workout), now: clock.now)
            lines.append("\(elapsed) | \(reads) | \(label) | \(phase)")
        }

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()
        record("climb saved, first look")

        #expect(reader.requestedWindows.count == 1)
        #expect(workout.heartRateTimeSeries.isEmpty)

        for delay in schedule.backoff {
            clock.advance(by: delay)

            if clock.now.timeIntervalSince(start) >= publishesAfter, !reader.hasPublished {
                reader.publish(lateSeries(climbStart: climbStart))
                lines.append(
                    stamp(clock.now.timeIntervalSince(start))
                        + " |          | wearable's companion app syncs into Apple Health"
                )
            }

            service.resumeTracking(modelContext: modelContext)
            await service.drainInFlightWork()
            record("scheduled look")

            if workout.avgHeartRate != nil { break }
        }

        // The point of the whole change: it landed, on a climb Ascend recorded, from a series
        // Health only wrote after Ascend had already looked five times.
        #expect(workout.avgHeartRate == 152)
        #expect(workout.maxHeartRate == 179)
        #expect(workout.caloriesBurned == 231)
        #expect(workout.heartRateTimeSeries.count == 4)
        #expect(service.phase(for: workout) == .notApplicable)

        // And it stops: nothing is left waking the app up for a climb that is now complete.
        #expect(service.hasScheduledWakeUp == false)

        let readsSpent = reader.requestedWindows.count
        #expect(readsSpent < schedule.attemptBudget)

        lines.append("")
        lines.append(
            "attached: avg \(workout.avgHeartRate ?? 0) bpm · max \(workout.maxHeartRate ?? 0) bpm"
                + " · \(Int(workout.caloriesBurned ?? 0)) kcal · \(workout.heartRateTimeSeries.count) samples"
        )
        lines.append("reads spent: \(readsSpent) of a \(schedule.attemptBudget)-attempt budget")
        lines.append("wake-up still scheduled for this climb: \(service.hasScheduledWakeUp)")

        let transcript = """
        Apple Health enrichment · #438 · late-publishing wearable
        =========================================================
        Climb recorded in Ascend at T+0 (20 min, headphone motion). Apple Health connected.
        Health holds nothing for this window until the companion app syncs at T+23:00.

        elapsed   | reads    | event | what the climber's heart-rate slot says
        ----------------------------------------------------------------------
        \(lines.joined(separator: "\n"))
        """

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try Data(transcript.utf8).write(
            to: URL(filePath: directory).appending(path: "enrichment-retry-timeline.txt")
        )
    }

    private func lateSeries(climbStart: Date) -> WorkoutMetrics {
        WorkoutMetrics(
            avgHeartRate: 152,
            maxHeartRate: 179,
            caloriesBurned: 231,
            heartRateTimeSeries: [
                HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(120), heartRate: 131),
                HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(480), heartRate: 158),
                HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(840), heartRate: 179),
                HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(1_140), heartRate: 141)
            ]
        )
    }

    private func formatted(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed.rounded())
        return String(format: "T+%02d:%02d", total / 60, total % 60)
    }

    private func describe(_ phase: AppleHealthEnrichmentService.Phase, now: Date) -> String {
        switch phase {
        case .notApplicable:
            return "heart rate attached - the chart replaces the card"
        case .connectionOffered:
            return "Connect Apple Health"
        case .unavailable:
            return "Apple Health unavailable"
        case .accessRevoked:
            return "Apple Health access is off"
        case .checking:
            return "Checking Apple Health"
        case .checksPaused:
            return "Checks are paused"
        case .stoppedLooking:
            return "Stopped looking - manual check still offered"
        case .waiting:
            return "Waiting on your wearable"
        }
    }
}

private final class TimelineClock: @unchecked Sendable {
    private(set) var now: Date

    init(start: Date) {
        now = start
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private final class TimelineMetricsReader: HealthKitMetricsReading {
    private(set) var requestedWindows: [ClosedRange<Date>] = []
    private(set) var hasPublished = false
    private var published: WorkoutMetrics?

    func publish(_ metrics: WorkoutMetrics) {
        published = metrics
        hasPublished = true
    }

    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics { WorkoutMetrics() }

    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        requestedWindows.append(dateRange)
        return published ?? WorkoutMetrics()
    }
}

@MainActor
private final class TimelineAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .connected

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { true }
}
