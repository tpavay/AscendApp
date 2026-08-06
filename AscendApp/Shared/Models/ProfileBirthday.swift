import Foundation

/// A calendar birthday, stored without a time zone so travel can never move it to another day.
struct ProfileBirthday: Codable, Hashable, RawRepresentable, Sendable {
    static let validAgeRange = 13...120

    let year: Int
    let month: Int
    let day: Int

    var rawValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              Self.isValid(year: year, month: month, day: day) else {
            return nil
        }

        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        precondition(
            components.year != nil && components.month != nil && components.day != nil,
            "A calendar date must contain year, month, and day components."
        )
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    func age(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        let current = calendar.dateComponents([.year, .month, .day], from: date)
        guard let currentYear = current.year,
              let currentMonth = current.month,
              let currentDay = current.day else {
            return nil
        }

        let birthdayHasOccurred = currentMonth > month ||
            (currentMonth == month && currentDay >= day)
        let age = currentYear - year - (birthdayHasOccurred ? 0 : 1)
        return age >= 0 ? age : nil
    }

    func date(calendar: Calendar = .current) -> Date? {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )
    }

    func hasValidProfileAge(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let age = age(on: date, calendar: calendar) else { return false }
        return Self.validAgeRange.contains(age)
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = utc
        }
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        )

        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }
}
