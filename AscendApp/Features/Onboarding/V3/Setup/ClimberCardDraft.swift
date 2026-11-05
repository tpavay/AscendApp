import Foundation

/// What the climber has entered on the climber card so far, and everything the card says about it.
///
/// Pure, so the age a birthday gives, the ranges, the steps and the tile text are tested without a
/// view. Everything is stored the way the profile stores it (centimetres, kilograms, a calendar
/// birthday) and shown in the phone's measurement system.
struct ClimberCardDraft: Equatable, Sendable {
    /// The ages the card accepts: 13 is the floor the privacy policy states.
    static let ageRange = 13...99

    static let heightInchesRange = 48...90
    static let weightPoundsRange = 80...400
    static let heightCentimetersRange = 122...229
    static let weightKilogramsRange = 36...181

    /// Where the first tap on a stepper starts, so an empty value never needs a keyboard.
    private static let startingHeightInches = 67
    private static let startingWeightPounds = 160
    private static let startingHeightCentimeters = 170
    private static let startingWeightKilograms = 72

    var gender: ProfileGender?
    var birthday: PreAuthOnboardingBirthday?
    var heightCm: Double?
    var weightKg: Double?
    var system: MeasurementSystem

    init(answers: PreAuthOnboardingAnswers, system: MeasurementSystem) {
        gender = answers.gender
        birthday = answers.birthday
        heightCm = answers.heightCm
        weightKg = answers.weightKg
        self.system = system
    }

    // MARK: - Gender

    /// The chips, in the order the design draws them.
    static let genderChoices: [(gender: ProfileGender, title: String)] = [
        (.man, "Male"),
        (.woman, "Female"),
        (.nonBinary, "Other"),
        (.preferNotToSay, "Prefer not to say")
    ]

    /// What the gender tile reads.
    var genderTileText: String? {
        switch gender {
        case .man: "Male"
        case .woman: "Female"
        case .nonBinary: "Other"
        case .preferNotToSay: "Private"
        case nil: nil
        }
    }

    // MARK: - Birthday and age

    /// The oldest and youngest birthdays the wheel offers on `date`.
    static func birthdayRange(on date: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let youngest = calendar.date(byAdding: .year, value: -ageRange.lowerBound, to: date) ?? date
        let oldest = calendar.date(byAdding: .year, value: -(ageRange.upperBound + 1), to: date).flatMap {
            calendar.date(byAdding: .day, value: 1, to: $0)
        } ?? date
        return oldest...youngest
    }

    /// The date the wheel shows before a birthday is chosen: about thirty years back.
    static func wheelStart(on date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: -30, to: date) ?? date
    }

    mutating func setBirthday(from date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        birthday = PreAuthOnboardingBirthday(year: year, month: month, day: day)
    }

    func birthdayDate(calendar: Calendar = .current) -> Date? {
        birthday.flatMap {
            calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day, hour: 12))
        }
    }

    /// The age the birthday gives on `date`, when it is one the card accepts.
    func age(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let birthday,
              let stored = ProfileBirthday(rawValue: String(format: "%04d-%02d-%02d", birthday.year, birthday.month, birthday.day)),
              let age = stored.age(on: date, calendar: calendar),
              Self.ageRange.contains(age) else { return nil }
        return age
    }

    // MARK: - Height

    /// Whole inches for an imperial display.
    var heightInches: Int? {
        heightCm.map { Int(($0 / 2.54).rounded()) }
    }

    var heightText: String? {
        guard let heightCm else { return nil }
        switch system {
        case .imperial:
            let inches = Int((heightCm / 2.54).rounded())
            return "\(inches / 12)'\(inches % 12)\""
        case .metric:
            return "\(Int(heightCm.rounded())) cm"
        }
    }

    /// Steps the height one unit - an inch or a centimetre - from where it is, or from the
    /// starting height when nothing is set. Never leaves the range.
    mutating func stepHeight(_ direction: Int) {
        switch system {
        case .imperial:
            let current = heightInches ?? Self.startingHeightInches - direction
            let next = min(max(current + direction, Self.heightInchesRange.lowerBound), Self.heightInchesRange.upperBound)
            heightCm = Double(next) * 2.54
        case .metric:
            let current = heightCm.map { Int($0.rounded()) } ?? Self.startingHeightCentimeters - direction
            let next = min(max(current + direction, Self.heightCentimetersRange.lowerBound), Self.heightCentimetersRange.upperBound)
            heightCm = Double(next)
        }
    }

    // MARK: - Weight

    var weightPounds: Int? {
        weightKg.map { Int(MeasurementSystem.metric.convertWeight($0, to: .imperial).rounded()) }
    }

    var weightText: String? {
        guard let weightKg else { return nil }
        switch system {
        case .imperial: return "\(weightPounds ?? 0) lb"
        case .metric: return "\(Int(weightKg.rounded())) kg"
        }
    }

    mutating func stepWeight(_ direction: Int) {
        switch system {
        case .imperial:
            let current = weightPounds ?? Self.startingWeightPounds - direction
            let next = min(max(current + direction, Self.weightPoundsRange.lowerBound), Self.weightPoundsRange.upperBound)
            weightKg = MeasurementSystem.imperial.convertWeight(Double(next), to: .metric)
        case .metric:
            let current = weightKg.map { Int($0.rounded()) } ?? Self.startingWeightKilograms - direction
            let next = min(max(current + direction, Self.weightKilogramsRange.lowerBound), Self.weightKilogramsRange.upperBound)
            weightKg = Double(next)
        }
    }

    // MARK: - Saving

    /// Skip leaves the whole card unset, clearing anything an earlier pass through the screen
    /// stored, so nothing the climber walked back from is published after sign-in.
    static func clearAnswers(in answers: inout PreAuthOnboardingAnswers) {
        answers.gender = nil
        answers.birthday = nil
        answers.heightCm = nil
        answers.weightKg = nil
    }

    /// Writes the card into the answers. The draft starts from the stored answers, so assigning
    /// each field keeps what was left alone and lets a tap on a chosen chip clear it.
    func apply(to answers: inout PreAuthOnboardingAnswers) {
        answers.gender = gender
        answers.birthday = age() == nil ? nil : birthday
        answers.heightCm = heightCm
        answers.weightKg = weightKg
    }
}
