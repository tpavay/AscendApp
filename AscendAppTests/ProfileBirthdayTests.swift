import Foundation
import Testing
@testable import AscendApp

struct ProfileBirthdayTests {
    @Test
    func rawValueRoundTripsOnlyRealCalendarDates() throws {
        let birthday = try #require(ProfileBirthday(rawValue: "1994-03-14"))

        #expect(birthday.rawValue == "1994-03-14")
        #expect(ProfileBirthday(rawValue: "1994-02-29") == nil)
        #expect(ProfileBirthday(rawValue: "not-a-date") == nil)
    }

    @Test
    func ageChangesOnTheBirthday() throws {
        let birthday = try #require(ProfileBirthday(rawValue: "1994-03-14"))

        #expect(birthday.age(on: date(2026, 3, 13), calendar: calendar) == 31)
        #expect(birthday.age(on: date(2026, 3, 14), calendar: calendar) == 32)
        #expect(birthday.age(on: date(2026, 8, 4), calendar: calendar) == 32)
    }

    @Test
    func leapDayBirthdayDoesNotAdvanceEarly() throws {
        let birthday = try #require(ProfileBirthday(rawValue: "2000-02-29"))

        #expect(birthday.age(on: date(2025, 2, 28), calendar: calendar) == 24)
        #expect(birthday.age(on: date(2025, 3, 1), calendar: calendar) == 25)
    }

    @Test
    func profileAgeAcceptsTheInclusiveLaunchRange() throws {
        let today = date(2026, 8, 4)
        let thirteen = try #require(ProfileBirthday(rawValue: "2013-08-04"))
        let oneHundredTwenty = try #require(ProfileBirthday(rawValue: "1906-08-04"))
        let tooYoung = try #require(ProfileBirthday(rawValue: "2013-08-05"))
        let tooOld = try #require(ProfileBirthday(rawValue: "1905-08-04"))

        #expect(thirteen.hasValidProfileAge(on: today, calendar: calendar))
        #expect(oneHundredTwenty.hasValidProfileAge(on: today, calendar: calendar))
        #expect(!tooYoung.hasValidProfileAge(on: today, calendar: calendar))
        #expect(!tooOld.hasValidProfileAge(on: today, calendar: calendar))
    }

    @Test
    func birthdayWinsWhileStoredAgeRemainsALegacyFallback() {
        let profileWithBirthday = UserDisplayNameData([
            "birth_date": "1994-03-14",
            "age": 99
        ])
        let legacyProfile = UserDisplayNameData(["age": 41])

        #expect(profileWithBirthday.age(on: date(2026, 8, 4), calendar: calendar) == 32)
        #expect(legacyProfile.age(on: date(2026, 8, 4), calendar: calendar) == 41)
    }

    @Test
    func invalidPrivateBirthdayFallsBackToTheStoredLegacyAge() {
        let profile = UserDisplayNameData([
            "birth_date": "1994-02-29",
            "age": 41
        ])

        #expect(profile.birthday == nil)
        #expect(profile.age(on: date(2026, 8, 4), calendar: calendar) == 41)
    }

    @Test
    func birthdayNeverEntersThePublicIdentityPayload() throws {
        let privateData: [String: Any] = [
            "displayName": "Maya Chen",
            "birth_date": "1994-03-14"
        ]
        let identity = try UserDataRepository.publicIdentity(
            userId: "user-123",
            userData: privateData,
            asOf: date(2026, 8, 4),
            calendar: calendar
        )
        let publication = try ProfileIdentityPersistenceAdapter.validatedFields(for: identity)
        let payload = ProfileRepository.publicIdentityPayload(
            identity,
            publication: publication,
            advancesIdentityVersion: true
        )

        #expect(payload["age"] as? Int == 32)
        #expect(payload["birth_date"] == nil)
        #expect(payload["birthday"] == nil)
        #expect(payload["date_of_birth"] == nil)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = utc
        }
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }
}
