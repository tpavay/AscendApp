import Foundation
import Testing
@testable import AscendApp

/// The pure rules under Apple Health import: overlap, which steps survive, what the notification
/// says, and how the Imports screen groups and words its rows.
@MainActor
struct AppleHealthImportPolicyTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Overlap

    @Test
    func windowsOverlapAtAMinuteOrMore() {
        let end = base.addingTimeInterval(1_800)
        #expect(AppleHealthImportPolicy.windowsOverlap(base, end, base.addingTimeInterval(1_740), end.addingTimeInterval(600)))
        #expect(!AppleHealthImportPolicy.windowsOverlap(base, end, base.addingTimeInterval(1_741), end.addingTimeInterval(600)))
        #expect(!AppleHealthImportPolicy.windowsOverlap(base, end, end, end.addingTimeInterval(600)))
        // One window inside the other overlaps by the shorter one's whole length.
        #expect(AppleHealthImportPolicy.windowsOverlap(base, end, base.addingTimeInterval(300), base.addingTimeInterval(600)))
    }

    // MARK: - What a workout may carry

    @Test
    func importableStepsKeepsHealthsNumberUntilItIsOneNoMachineProduces() {
        let thirtyMinutes: TimeInterval = 1_800
        #expect(AppleHealthImportPolicy.importableSteps(4_912, duration: thirtyMinutes) == 4_912)
        #expect(AppleHealthImportPolicy.importableSteps(7_500, duration: thirtyMinutes) == 7_500, "above the ceiling is kept, only off the boards")
        #expect(AppleHealthImportPolicy.importableSteps(9_000, duration: thirtyMinutes) == nil, "300 a minute is refused")
        #expect(AppleHealthImportPolicy.importableSteps(ClimbPacePolicy.maximumSteps + 1, duration: 24 * 3_600) == nil)
        #expect(AppleHealthImportPolicy.importableSteps(nil, duration: thirtyMinutes) == nil)
        #expect(AppleHealthImportPolicy.importableSteps(0, duration: thirtyMinutes) == nil)
    }

    @Test
    func aWorkoutIsOnlyAClimbBetweenASecondAndADay() {
        #expect(!AppleHealthImportPolicy.isImportableDuration(0))
        #expect(AppleHealthImportPolicy.isImportableDuration(1))
        #expect(AppleHealthImportPolicy.isImportableDuration(24 * 3_600))
        #expect(!AppleHealthImportPolicy.isImportableDuration(24 * 3_600 + 1))
    }

    // MARK: - Notification

    @Test
    func theNotificationNamesExactStepsAndNeverATilde() {
        let content = AppleHealthImportPolicy.notificationContent(steps: 4_912)
        #expect(content.title == "Climb imported")
        #expect(content.body == "Your 4,912-step stair stepper workout from Apple Health is in. Tap to add a note or photo.")
        #expect(!content.body.contains("~"))

        let missing = AppleHealthImportPolicy.notificationContent(steps: nil)
        #expect(missing.title == "Climb imported")
        #expect(!missing.body.contains("-step"))
    }

    // MARK: - Imports screen

    @Test
    func theImportsScreenGroupsWaitingFirstThenThisWeekThenEarlier() {
        var calendar = WeekConfiguration.calendar(timeZone: TimeZone(identifier: "UTC")!)
        calendar.locale = Locale(identifier: "en_US")
        // Thursday 2026-10-29 12:00 UTC: this week began Monday the 26th.
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        let today = HealthWorkoutRecord(snapshot: snapshot(start: now.addingTimeInterval(-3_600), steps: 4_912))
        let tuesday = HealthWorkoutRecord(snapshot: snapshot(start: now.addingTimeInterval(-2 * 86_400), steps: 3_207))
        let lastWeek = HealthWorkoutRecord(snapshot: snapshot(start: now.addingTimeInterval(-7 * 86_400), steps: 2_744))
        let waiting = HealthWorkoutRecord(snapshot: snapshot(start: now.addingTimeInterval(-86_400), steps: 3_000))
        let skipped = HealthWorkoutRecord(snapshot: snapshot(start: now.addingTimeInterval(-86_400), steps: 1))
        let covered = HealthWorkoutRecord(snapshot: snapshot(start: now.addingTimeInterval(-86_400), steps: 2))
        let climbIDs = [UUID(), UUID(), UUID()]
        for (record, id) in zip([today, tuesday, lastWeek], climbIDs) {
            record.state = .imported
            record.importedWorkoutID = id
        }
        skipped.state = .skipped
        covered.state = .overlapsLiveClimb

        let sections = ImportsSections.make(
            records: [lastWeek, skipped, today, covered, waiting, tuesday],
            climbs: [:],
            now: now,
            calendar: calendar
        )

        #expect(sections.notImported.map(\.steps) == [3_000])
        #expect(sections.thisWeek.map(\.steps) == [4_912, 3_207], "newest first")
        #expect(sections.earlier.map(\.steps) == [2_744])
        #expect(sections.notImported.allSatisfy { !$0.isImported })
        #expect(sections.thisWeek.allSatisfy { $0.isImported })
    }

    @Test
    func anImportedRowShowsTheClimbsOwnNumbersAfterAnEdit() {
        let record = HealthWorkoutRecord(snapshot: snapshot(start: base, steps: 4_912))
        let climbID = UUID()
        record.state = .imported
        record.importedWorkoutID = climbID

        let edited = ImportsSections.make(
            records: [record],
            climbs: [climbID: (steps: 5_020, duration: 3_700)],
            now: base
        )
        #expect(edited.thisWeek.first?.steps == 5_020)
        #expect(edited.thisWeek.first?.duration == 3_700)

        let missing = ImportsSections.make(
            records: [record],
            climbs: [climbID: (steps: 0, duration: 3_700)],
            now: base
        )
        #expect(missing.thisWeek.first?.steps == nil, "a climb back to no steps reads as a dash")
    }

    @Test
    func rowsWordThemselvesTheWayTheMockDoes() {
        #expect(ImportsRowFormat.stepsText(4_912) == "4,912 steps")
        #expect(ImportsRowFormat.stepsText(nil) == "Add steps")
        #expect(ImportsRowFormat.durationText(3_770) == "1:02:50")
        #expect(ImportsRowFormat.durationText(2_472) == "41:12")
        #expect(ImportsRowFormat.durationText(2_105) == "35:05")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        #expect(ImportsRowFormat.whenText(now, now: now, calendar: calendar).hasPrefix("Today · "))
        #expect(ImportsRowFormat.whenText(now.addingTimeInterval(-86_400), now: now, calendar: calendar).hasPrefix("Yesterday · "))
        #expect(ImportsRowFormat.whenText(now.addingTimeInterval(-5 * 86_400), now: now, calendar: calendar).contains(" · "))
    }

    // MARK: - The Climb sheet button

    @Test
    func theHealthButtonSaysWhatItDoes() {
        #expect(AppleHealthEntry.connect.title == "Connect Health")
        #expect(AppleHealthEntry.viewImports(badge: 0).title == "View imports")
        #expect(AppleHealthEntry.viewImports(badge: 2).title == "View imports")
        #expect(AppleHealthEntry.viewImports(badge: 2).accessibilityLabel == "View imports, 2 waiting")
        #expect(AppleHealthEntry.viewImports(badge: 0).accessibilityLabel == "View imports")
    }

    private func snapshot(start: Date, steps: Int) -> HealthWorkoutSnapshot {
        HealthWorkoutSnapshot(
            uuid: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            duration: 1_800,
            steps: steps
        )
    }
}
