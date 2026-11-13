import Foundation
import Testing

@testable import AscendApp

/// What the Log a climb screen's keypad builds, before anything is saved: the two numbers, the
/// floors conversion, and the verdict that decides whether Save is allowed.
struct LoggedClimbInputTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func input(steps: String, time: String, unit: LoggedClimbInput.Unit = .steps) -> LoggedClimbInput {
        var input = LoggedClimbInput(date: now)
        input.select(unit: unit)
        steps.compactMap(\.wholeNumberValue).forEach { input.appendAmountDigit($0) }
        time.compactMap(\.wholeNumberValue).forEach { input.timeEntry.append($0) }
        return input
    }

    // MARK: - The console time

    @Test
    func timeFillsFromTheRightLikeAConsole() {
        var entry = ConsoleTimeEntry()
        #expect(entry.display == "0:00")
        #expect(entry.seconds == nil)

        entry.append(4)
        #expect(entry.display == "0:04")
        entry.append(0)
        entry.append(0)
        entry.append(0)
        #expect(entry.display == "40:00")
        #expect(entry.seconds == 2_400)

        entry.append(1)
        #expect(entry.display == "4:00:01")
        #expect(entry.seconds == TimeInterval(4 * 3_600 + 1))
    }

    @Test
    func anHourTypedAsMinutesReadsAsAnHour() {
        var entry = ConsoleTimeEntry()
        [6, 0, 0, 0].forEach { entry.append($0) }

        #expect(entry.display == "60:00")
        #expect(entry.seconds == 3_600)
    }

    @Test
    func secondsPastFiftyNineAreNotATime() {
        var entry = ConsoleTimeEntry()
        [4, 0, 7, 5].forEach { entry.append($0) }

        #expect(!entry.isValid)
        #expect(entry.seconds == nil)
    }

    @Test
    func minutesPastFiftyNineAreNotATimeOnceThereAreHours() {
        var entry = ConsoleTimeEntry()
        [1, 7, 0, 0, 0].forEach { entry.append($0) } // 1:70:00

        #expect(!entry.isValid)
    }

    @Test
    func deleteRemovesTheLastDigitAndAZeroAloneTypesNothing() {
        var entry = ConsoleTimeEntry()
        entry.append(0)
        #expect(entry.isEmpty)

        [2, 5, 3, 0].forEach { entry.append($0) }
        #expect(entry.display == "25:30")
        entry.deleteLast()
        #expect(entry.display == "2:53")
    }

    @Test
    func timeStopsAtSixDigits() {
        var entry = ConsoleTimeEntry()
        for _ in 0..<9 { entry.append(1) }

        #expect(entry.digits.count == ConsoleTimeEntry.maximumDigits)
    }

    @Test
    func theSameAsLastChipTypesTheDurationBackAsAConsoleWould() {
        #expect(LogClimbViewModel.consoleDigits(for: 2_400) == [4, 0, 0, 0])
        // 1:02:05 is 3,725 seconds.
        #expect(LogClimbViewModel.consoleDigits(for: 3_725) == [1, 0, 2, 0, 5])
    }

    // MARK: - Steps and floors

    @Test
    func floorsConvertToStepsWithTheSharedRate() {
        let input = Self.input(steps: "200", time: "4000", unit: .floors)

        #expect(input.floors == 200)
        #expect(input.steps == 200 * FloorsClimbed.stepsPerFloor)
        #expect(input.steps == Workout.floorsToSteps(200))
    }

    @Test
    func stepsDeriveTheirFloorsWithTheSharedRounding() {
        let input = Self.input(steps: "3200", time: "4000")

        #expect(input.steps == 3_200)
        #expect(input.floors == Workout.stepsToFloors(3_200))
        #expect(input.floors == 200)
    }

    @Test
    func switchingUnitKeepsWhatWasTyped() {
        var input = Self.input(steps: "3200", time: "")
        input.select(unit: .floors)

        #expect(input.amount == 3_200)
        #expect(input.steps == 3_200 * FloorsClimbed.stepsPerFloor)
    }

    @Test
    func theAmountHasNoLeadingZerosAndStopsAtSixDigits() {
        var input = LoggedClimbInput(date: Self.now)
        input.appendAmountDigit(0)
        #expect(input.amount == nil)

        for _ in 0..<9 { input.appendAmountDigit(9) }
        #expect(input.amountDigits.count == LoggedClimbInput.maximumAmountDigits)
    }

    // MARK: - The verdict

    @Test
    func saveWaitsForBothNumbers() {
        #expect(LoggedClimbValidation.validate(Self.input(steps: "", time: "4000"), now: Self.now) == .incomplete)
        #expect(LoggedClimbValidation.validate(Self.input(steps: "3200", time: ""), now: Self.now) == .incomplete)
    }

    @Test
    func anOrdinaryClimbIsReady() {
        #expect(
            LoggedClimbValidation.validate(Self.input(steps: "3200", time: "4000"), now: Self.now)
                == .ready(.withinCeiling)
        )
    }

    @Test
    func theMocksImpossibleClimbIsRefusedWithTheMocksMessage() {
        let validation = LoggedClimbValidation.validate(
            Self.input(steps: "49120", time: "4000"),
            now: Self.now
        )

        #expect(validation == .refused(.impossiblePace(stepsPerMinute: 1_228)))
        guard case .refused(let refusal) = validation else { return }
        #expect(refusal.message == "That's 1,228 steps a minute. Check the steps or time.")
    }

    @Test
    func aPaceBetweenTheCeilingAndTheLineIsReadyButFlagged() {
        // 7,500 steps in 30:00 is 250 a minute.
        let validation = LoggedClimbValidation.validate(Self.input(steps: "7500", time: "3000"), now: Self.now)

        guard case .ready(let verdict) = validation, case .aboveCeiling = verdict else {
            Issue.record("expected ready(aboveCeiling), got \(validation)")
            return
        }
        #expect(verdict.leaderboardStatus == .excluded)
    }

    @Test
    func aClimbCannotStartInTheFuture() {
        var input = Self.input(steps: "3200", time: "4000")
        input.date = Self.now.addingTimeInterval(3_600)

        #expect(LoggedClimbValidation.validate(input, now: Self.now) == .refused(.startsInTheFuture))

        input.date = Self.now.addingTimeInterval(30)
        #expect(
            LoggedClimbValidation.validate(input, now: Self.now) == .ready(.withinCeiling),
            "a few seconds of clock skew is not tomorrow"
        )
    }

    @Test
    func aClimbHoldsNoMoreThanTheCloudAccepts() {
        // 7,500 floors is 120,000 steps - the cap - and 7,501 is past it.
        let atTheCap = Self.input(steps: "7500", time: "240000", unit: .floors)
        let pastTheCap = Self.input(steps: "7501", time: "240000", unit: .floors)

        #expect(LoggedClimbValidation.validate(atTheCap, now: Self.now) == .ready(.withinCeiling))
        #expect(LoggedClimbValidation.validate(pastTheCap, now: Self.now) == .refused(.tooManySteps))
    }

    @Test
    func aClimbRunsNoLongerThanADay() {
        // 25:00:00.
        let validation = LoggedClimbValidation.validate(Self.input(steps: "3000", time: "250000"), now: Self.now)
        #expect(validation == .refused(.tooLong))
    }

    @Test
    func aTimeThatIsNotATimeIsRefusedBeforeAnythingElse() {
        let validation = LoggedClimbValidation.validate(Self.input(steps: "3200", time: "4075"), now: Self.now)
        #expect(validation == .refused(.timeNotReal))
    }
}
