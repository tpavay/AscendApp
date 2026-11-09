import Foundation
import HealthKit
import Testing
@testable import AscendApp

/// Which Health workouts Ascend reads as a stair stepper session, and what it says about the ones
/// it reads and does not count, so the way other watches and apps label the machine shows up in
/// the numbers.
@MainActor
@Suite(.serialized)
struct AppleHealthWorkoutSkipTests {
    // MARK: - Activity types

    @Test
    func theReadCoversTheTwoStairActivityTypes() {
        #expect(HealthKitWorkoutReader.stairActivityTypes == [.stairClimbing, .stairs])
    }

    @Test
    func theReadsPredicateMatchesEachStairTypeAndNoOther() {
        let format = HealthKitWorkoutReader.stairWorkoutPredicate().predicateFormat
        for type in HealthKitWorkoutReader.stairActivityTypes {
            #expect(format.contains("\(type.rawValue)"), "\(type.rawValue) is missing from \(format)")
        }
        #expect(!format.contains("\(HKWorkoutActivityType.running.rawValue)"), "\(format)")
        #expect(format.components(separatedBy: " OR ").count == HealthKitWorkoutReader.stairActivityTypes.count, "\(format)")
    }

    // MARK: - What a skip says

    @Test
    func aStairWorkoutTooLongToBeAClimbIsReportedOnceAndNeverFiled() async throws {
        let harness = try AppleHealthImportHarness()
        let skipped = harness.addWorkout(
            daysAgo: 3,
            steps: 3_000,
            minutes: 25 * 60,
            activityTypeRawValue: HKWorkoutActivityType.stairs.rawValue,
            sourceBundleIdentifier: "com.garmin.connect.mobile"
        )
        harness.addWorkout(daysAgo: 1, steps: 3_000)
        await harness.service.syncNow()
        await harness.service.syncNow()

        #expect(try harness.records().count == 1, "the day-long workout is not a climb")
        let skip = try #require(harness.skipReporter.skips.first)
        #expect(harness.skipReporter.skips.count == 1, "the anchor has moved past it")
        #expect(skip.uuid == skipped.uuid)
        #expect(skip.reason == .duration)
        #expect(skip.activityTypeRawValue == HKWorkoutActivityType.stairs.rawValue)
        #expect(skip.sourceBundleIdentifier == "com.garmin.connect.mobile")
    }

    @Test
    func aWorkoutALiveClimbCoversIsReportedAndIsNeverImportedMergedOrOffered() async throws {
        let harness = try AppleHealthImportHarness()
        let start = harness.referenceNow.addingTimeInterval(-2 * 3600)
        let live = Workout(
            name: "Empire State Building",
            date: start,
            duration: 30 * 60,
            steps: 1_860,
            floors: Workout.stepsToFloors(1_860),
            source: .headphoneMotion
        )
        harness.context.insert(live)
        try harness.context.save()
        let watch = harness.addWorkout(daysAgo: 2.0 / 24, steps: 2_400, minutes: 32, averageHeartRate: 150, energy: 300)
        await harness.service.syncNow()
        await harness.service.syncNow()

        let record = try #require(try harness.record(watch))
        #expect(record.state == .overlapsLiveClimb)
        #expect(try harness.climbs().count == 1, "the live climb is the climb")
        let climb = try #require(try harness.climbs().first)
        #expect(climb.steps == 1_860, "nothing of the watch's workout is merged into it")
        #expect(climb.avgHeartRate == nil)
        #expect(climb.caloriesBurned == nil)
        #expect(climb.duration == 30 * 60)
        #expect(harness.service.waitingWorkoutCount == 0, "and nothing waits for the climber to answer")
        #expect(harness.service.badgeCount == 0)
        #expect(harness.service.homeNotice == nil)
        #expect(harness.notifier.imported.isEmpty)
        #expect(harness.skipReporter.skips.map(\.reason) == [.overlapsLiveClimb])

        // Asking for it by hand changes nothing: the state is terminal.
        let batch = await harness.service.importRecords(withUUIDs: [watch.uuid.uuidString])
        #expect(batch.isEmpty)
        #expect(try harness.climbs().count == 1)
    }

    @Test
    func theHistoryReadReportsWhatItPassesOver() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 60, steps: 3_000)
        let blip = harness.addWorkout(daysAgo: 70, steps: nil, minutes: 0.005)

        let history = try await HealthHistory.load(using: harness.reader, skipReporter: harness.skipReporter)

        #expect(history.workouts.count == 1)
        #expect(harness.skipReporter.skips.map(\.uuid) == [blip.uuid])
        #expect(harness.skipReporter.skips.first?.reason == .duration)
    }

    // MARK: - The event

    @Test
    func theEventCarriesTheActivityTypeTheWritingAppAndACoarseDurationAndNothingElse() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = HealthWorkoutSnapshot(
            uuid: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(90_000),
            duration: 90_000,
            steps: 4_000,
            averageHeartRate: 150,
            activityTypeRawValue: HKWorkoutActivityType.stairs.rawValue,
            sourceBundleIdentifier: "com.garmin.connect.mobile"
        )

        let record = AppleHealthImportAnalyticsEvent.workoutSkipped(HealthWorkoutSkip(snapshot, reason: .duration)).record

        #expect(record.name == "apple_health_workout_skipped")
        #expect(record.parameters == [
            "reason": .string("duration"),
            "activity_type": .int(Int(HKWorkoutActivityType.stairs.rawValue)),
            "source_bundle_id": .string("com.garmin.connect.mobile"),
            "duration_bucket": .string("over_24h")
        ], "no date, no steps, no heart rate, no identifier")
        #expect(record.destinations == [.analytics])
    }

    @Test
    func anAppleWatchReportsAsAppleHealthAndNeverAsThatWatch() {
        #expect(
            AppleHealthImportAnalyticsEvent.reportedBundleIdentifier("com.apple.health.3F2504E0-4F89-11D3-9A0C-0305E82C3301")
                == "com.apple.health"
        )
        #expect(AppleHealthImportAnalyticsEvent.reportedBundleIdentifier("com.apple.health") == "com.apple.health")
        #expect(AppleHealthImportAnalyticsEvent.reportedBundleIdentifier("com.apple.healthy") == "com.apple.healthy")
        #expect(AppleHealthImportAnalyticsEvent.reportedBundleIdentifier("com.garmin.connect.mobile") == "com.garmin.connect.mobile")
        #expect(AppleHealthImportAnalyticsEvent.reportedBundleIdentifier(nil) == "unknown")
        #expect(AppleHealthImportAnalyticsEvent.reportedBundleIdentifier("") == "unknown")
    }

    @Test(arguments: [
        (0.5, "under_1s"), (30, "under_1m"), (60, "1_to_10m"), (599, "1_to_10m"), (600, "10_to_30m"),
        (1_800, "30_to_60m"), (3_600, "1_to_2h"), (7_200, "2_to_24h"), (86_400, "2_to_24h"), (86_401, "over_24h")
    ] as [(TimeInterval, String)])
    func aDurationReportsAsOneOfAFewBuckets(duration: TimeInterval, bucket: String) {
        #expect(AppleHealthImportAnalyticsEvent.durationBucket(duration) == bucket)
    }

    @Test
    func theReporterSendsOneEventForAWorkoutHoweverManyReadsSeeIt() {
        var sent: [TelemetryRecord] = []
        let reporter = HealthWorkoutSkipReporter(track: { sent.append($0.record) })
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let first = HealthWorkoutSnapshot(uuid: UUID(), startDate: start, endDate: start, duration: 0)
        let second = HealthWorkoutSnapshot(uuid: UUID(), startDate: start, endDate: start, duration: 0)

        reporter.report(HealthWorkoutSkip(first, reason: .duration))
        reporter.report(HealthWorkoutSkip(first, reason: .duration))
        reporter.report(HealthWorkoutSkip(second, reason: .duration))

        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.name == "apple_health_workout_skipped" })
    }
}
