import Foundation

/// What the climber has entered on the profile screen so far, and everything the screen says about it.
///
/// Pure, so the leaderboard row's text, the initials, the age a birthday gives and what reaches the
/// answers are tested without a view. Everything is stored the way the profile stores it
/// (centimetres, kilograms, a calendar birthday) and shown in the climber's unit.
struct ProfileSetupDraft: Equatable, Sendable {
    /// The ages the screen accepts: 13 is the floor the privacy policy states.
    static let ageRange = 13...99

    var firstName = "" {
        didSet { refreshBoardName() }
    }
    var lastName = "" {
        didSet { refreshBoardName() }
    }
    var photoFileName: String?
    var gender: ProfileGender?
    var birthday: PreAuthOnboardingBirthday?
    var heightCm: Double?
    var weightKg: Double?
    var system: MeasurementSystem

    /// What the typed name publishes as, or `nil` while nothing is typed or the policy refuses it.
    /// Held rather than computed because the row reads it several times a render and screening
    /// runs a pattern per blocked term.
    private(set) var boardName: String?

    /// Read only: the city is claimed on the next step, and shows on the row once it is.
    private let cityName: String?

    init(answers: PreAuthOnboardingAnswers, system: MeasurementSystem) {
        firstName = answers.firstName ?? ""
        lastName = answers.lastName ?? ""
        photoFileName = answers.profilePhotoFileName
        gender = answers.gender
        birthday = answers.birthday
        heightCm = answers.heightCm
        weightKg = answers.weightKg
        cityName = answers.city?.city
        self.system = system
        refreshBoardName()
    }

    private mutating func refreshBoardName() {
        boardName = try? DisplayNamePolicy.typedBoardName(firstName: firstName, lastName: lastName)
    }

    // MARK: - The leaderboard row

    private var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLastName: String { lastName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Something is typed and the policy refuses it, so it would never reach a leaderboard.
    var isNameRefused: Bool {
        boardName == nil && !(trimmedFirstName.isEmpty && trimmedLastName.isEmpty)
    }

    /// What this climber publishes as: the typed name, or the name an account with none is given,
    /// which is the whole point of the preview: this is you right now, so fix it.
    var displayName: String {
        boardName ?? SignInNamePlaceholder.boardName
    }

    /// The first letter of each part of the name on the row.
    var initials: String {
        let parts = boardName == nil
            ? [SignInNamePlaceholder.firstName, SignInNamePlaceholder.lastName]
            : [trimmedFirstName, trimmedLastName]
        return parts
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
    }

    /// Gender, age and city in that order, whatever is set; `nil` while nothing is. A private
    /// gender shows nothing, and the birthday itself never shows, only the age it gives.
    func subline(on date: Date = .now, calendar: Calendar = .current) -> String? {
        let parts = [genderLabel, age(on: date, calendar: calendar).map { $0.formatted() }, cityName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// What the subline says for the gender: `M`, `F` or `Other`, and nothing for Private.
    var genderLabel: String? {
        switch gender {
        case .man: "M"
        case .woman: "F"
        case .nonBinary: "Other"
        case .preferNotToSay, nil: nil
        }
    }

    // MARK: - Name

    /// What a name field may hold beside the other one, so the two always compose to a board name
    /// inside `DisplayNamePolicy.maximumLength`.
    static func cappedName(_ typed: String, beside other: String) -> String {
        let otherName = other.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = otherName.isEmpty ? 0 : otherName.count + 1
        return String(typed.prefix(max(DisplayNamePolicy.maximumLength - taken, 0)))
    }

    // MARK: - Gender

    /// The four segments, in the order the design draws them.
    static let genderChoices: [(gender: ProfileGender, title: String)] = [
        (.man, "Male"),
        (.woman, "Female"),
        (.nonBinary, "Other"),
        (.preferNotToSay, "Private")
    ]

    // MARK: - Birthday and age

    /// A stored birthday's year is Gregorian whatever calendar the phone uses, because the profile,
    /// the rules and the server all read it that way. Only the device calendar's time zone counts.
    private static func gregorian(from deviceCalendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = deviceCalendar.timeZone
        return gregorian
    }

    /// The oldest and youngest birthdays the wheel offers on `date`.
    static func birthdayRange(on date: Date = .now, calendar deviceCalendar: Calendar = .current) -> ClosedRange<Date> {
        let calendar = gregorian(from: deviceCalendar)
        let youngest = calendar.date(byAdding: .year, value: -ageRange.lowerBound, to: date) ?? date
        let oldest = calendar.date(byAdding: .year, value: -(ageRange.upperBound + 1), to: date).flatMap {
            calendar.date(byAdding: .day, value: 1, to: $0)
        } ?? date
        return oldest...youngest
    }

    /// Where the wheel opens before a birthday is chosen: about thirty years back. Opening there
    /// never saves it.
    static func wheelStart(on date: Date = .now, calendar deviceCalendar: Calendar = .current) -> Date {
        gregorian(from: deviceCalendar).date(byAdding: .year, value: -30, to: date) ?? date
    }

    mutating func setBirthday(from date: Date, calendar deviceCalendar: Calendar = .current) {
        let parts = Self.gregorian(from: deviceCalendar).dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        birthday = PreAuthOnboardingBirthday(year: year, month: month, day: day)
    }

    func birthdayDate(calendar deviceCalendar: Calendar = .current) -> Date? {
        birthday.flatMap {
            Self.gregorian(from: deviceCalendar).date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day, hour: 12))
        }
    }

    /// The age the birthday gives on `date`, when it is one the screen accepts.
    func age(on date: Date = .now, calendar deviceCalendar: Calendar = .current) -> Int? {
        birthday.flatMap { Self.age(of: $0, on: date, calendar: deviceCalendar) }
    }

    /// The age `birthday` gives on `date`, when it is one the screen accepts. The one rule for every
    /// screen that says an age back from the answers.
    static func age(of birthday: PreAuthOnboardingBirthday, on date: Date = .now, calendar deviceCalendar: Calendar = .current) -> Int? {
        guard let stored = ProfileBirthday(rawValue: String(format: "%04d-%02d-%02d", birthday.year, birthday.month, birthday.day)),
              let age = stored.age(on: date, calendar: gregorian(from: deviceCalendar)),
              ageRange.contains(age) else { return nil }
        return age
    }

    /// `Jun 14, 1996 · 30` for the Birthday row, or `nil` for "Not set". The date appears on this
    /// screen only, on the device; nothing public ever carries it.
    func birthdayRowText(
        on date: Date = .now,
        calendar deviceCalendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let age = age(on: date, calendar: deviceCalendar),
              let day = birthdayDate(calendar: deviceCalendar) else { return nil }

        let gregorian = Self.gregorian(from: deviceCalendar)
        let formatted = day.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: gregorian, timeZone: gregorian.timeZone)
        )
        return "\(formatted) \u{00B7} \(age)"
    }

    // MARK: - Height and weight rows

    var heightRowText: String? {
        heightCm.map { ProfileMeasures.heightText(centimeters: $0, system: system) }
    }

    var weightRowText: String? {
        weightKg.map { ProfileMeasures.weightText(kilograms: $0, system: system) }
    }

    // MARK: - Saving

    /// Skip leaves the whole screen unset, clearing anything an earlier pass through it stored, so
    /// nothing the climber walked back from is published after sign-in.
    static func clearAnswers(in answers: inout PreAuthOnboardingAnswers) {
        answers.firstName = nil
        answers.lastName = nil
        answers.profilePhotoFileName = nil
        answers.gender = nil
        answers.birthday = nil
        answers.heightCm = nil
        answers.weightKg = nil
    }

    /// Writes the screen into the answers. The draft starts from the stored answers, so assigning
    /// each field keeps what was left alone and lets a tap on a chosen segment clear it.
    func apply(to answers: inout PreAuthOnboardingAnswers) {
        answers.firstName = trimmedFirstName.isEmpty ? nil : trimmedFirstName
        answers.lastName = trimmedLastName.isEmpty ? nil : trimmedLastName
        answers.profilePhotoFileName = photoFileName
        answers.gender = gender
        answers.birthday = age() == nil ? nil : birthday
        answers.heightCm = heightCm
        answers.weightKg = weightKg
    }
}
