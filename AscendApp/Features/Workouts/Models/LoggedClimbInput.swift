import Foundation

/// What the Log a climb screen has collected so far, in the terms the climber typed it.
///
/// Pure value logic, so everything that decides whether a climb can be saved is testable without
/// a view tree: the keypad feeds digit buffers into it and the screen only renders what it says.
struct LoggedClimbInput: Equatable, Sendable {
    /// What the big number is counting. Floors convert to steps with the same fixed rate every
    /// other surface uses (`FloorsClimbed.stepsPerFloor`), so a climb logged in floors and one
    /// logged in steps are the same climb.
    enum Unit: String, CaseIterable, Sendable {
        case steps
        case floors
    }

    /// Longest number the keypad accepts for the amount, so a held key cannot grow past what a
    /// climb can hold.
    static let maximumAmountDigits = 6

    var date: Date
    var unit: Unit = .steps
    var amountDigits: String = ""
    var timeEntry = ConsoleTimeEntry()

    init(date: Date = Date()) {
        self.date = date
    }

    /// The typed amount in whichever unit is selected, or nil while the field is empty.
    var amount: Int? {
        guard !amountDigits.isEmpty else { return nil }
        return Int(amountDigits)
    }

    /// Steps for the climb: typed directly, or converted from floors. Nil while nothing is typed.
    var steps: Int? {
        guard let amount else { return nil }
        switch unit {
        case .steps:
            return amount
        case .floors:
            return Workout.floorsToSteps(amount)
        }
    }

    /// Floors for the climb: typed directly, or derived from steps with the shared rounding.
    var floors: Int? {
        guard let amount else { return nil }
        switch unit {
        case .steps:
            return Workout.stepsToFloors(amount)
        case .floors:
            return amount
        }
    }

    var duration: TimeInterval? {
        timeEntry.seconds
    }

    mutating func appendAmountDigit(_ digit: Int) {
        guard (0...9).contains(digit), amountDigits.count < Self.maximumAmountDigits else { return }
        // No leading zeros: a typed 0 on an empty field is nothing, not a number.
        if amountDigits.isEmpty, digit == 0 { return }
        amountDigits.append(String(digit))
    }

    mutating func deleteLastAmountDigit() {
        guard !amountDigits.isEmpty else { return }
        amountDigits.removeLast()
    }

    /// Switching unit keeps what the climber typed rather than converting it: the number on screen
    /// is the number they read off the console, and silently turning 3,200 steps into 200 floors
    /// would change what they meant.
    mutating func select(unit: Unit) {
        self.unit = unit
    }
}

/// A time typed digit by digit, the way a console shows it.
///
/// Digits fill from the right: `4` `0` `0` `0` reads 40:00, and a fifth digit turns it into
/// 1:40:00. Up to four digits is minutes and seconds, so 60:00 is an hour; past that the left
/// digits are hours. Seconds always run 00 to 59, and minutes do once there are hours - anything
/// else is not a time a console ever shows, and `isValid` says so rather than guessing.
struct ConsoleTimeEntry: Equatable, Sendable {
    static let maximumDigits = 6

    private(set) var digits: String = ""

    var isEmpty: Bool {
        digits.isEmpty
    }

    mutating func append(_ digit: Int) {
        guard (0...9).contains(digit), digits.count < Self.maximumDigits else { return }
        if digits.isEmpty, digit == 0 { return }
        digits.append(String(digit))
    }

    mutating func deleteLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    private var components: (hours: Int, minutes: Int, seconds: Int) {
        let padded = String(repeating: "0", count: max(0, Self.maximumDigits - digits.count)) + digits
        let characters = Array(padded)
        let hours = Int(String(characters[0..<2])) ?? 0
        let minutes = Int(String(characters[2..<4])) ?? 0
        let seconds = Int(String(characters[4..<6])) ?? 0
        return (hours, minutes, seconds)
    }

    /// Whether the digits read as a time a console could show.
    var isValid: Bool {
        guard !digits.isEmpty else { return true }
        let parts = components
        if parts.seconds > 59 { return false }
        if digits.count > 4, parts.minutes > 59 { return false }
        return true
    }

    /// The typed time in seconds, or nil while empty or not a real time.
    var seconds: TimeInterval? {
        guard !digits.isEmpty, isValid else { return nil }
        let parts = components
        let total = parts.hours * 3_600 + parts.minutes * 60 + parts.seconds
        return total > 0 ? TimeInterval(total) : nil
    }

    /// What the field shows: `0:00` while empty, `40:00` for forty minutes, `1:40:00` past an hour.
    var display: String {
        guard !digits.isEmpty else { return "0:00" }
        let parts = components
        if digits.count > 4 {
            return String(format: "%d:%02d:%02d", parts.hours, parts.minutes, parts.seconds)
        }
        return String(format: "%d:%02d", parts.hours * 60 + parts.minutes, parts.seconds)
    }
}
