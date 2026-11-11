import Foundation

/// What the pre-sign-in answers add to a profile, decided from the answers and the profile as it
/// already stands.
///
/// Nothing is overwritten. A climber who signs in to an account that already carries a birthday,
/// a body measurement or a city keeps it: the answers were given on a phone that did not know who
/// was holding it, so they only ever fill a blank. Every value is held to the bound the profile
/// rules enforce, so a write cannot be refused for a value the flow let through.
struct OnboardingProfileFill: Equatable, Sendable {
    var birthday: ProfileBirthday?
    var gender: ProfileGender?
    var weightKg: Double?
    var heightCm: Double?
    var city: PreAuthOnboardingCity?
    /// The name typed on 08, only when it makes a board name the rules accept.
    var name: Name?
    /// The picked photo's file name in ``OnboardingProfilePhotoStore``, for an account with none.
    var photoFileName: String?

    /// A half the climber left empty is stored empty, which is how a profile holds no name part.
    struct Name: Equatable, Sendable {
        var firstName: String
        var lastName: String
    }

    /// Whether anything in the fill is a demographic, which `updateOnboardingDemographics` writes.
    var hasDemographics: Bool {
        birthday != nil || gender != nil || weightKg != nil || heightCm != nil || city != nil
    }

    var isEmpty: Bool {
        !hasDemographics && name == nil && photoFileName == nil
    }

    /// The bounds `firestore.rules` and the profile editors share.
    static let weightKgRange = 0.0...400.0
    static let heightCmRange = 90.0...240.0
    static let locationTextLength = 1...120

    /// - Parameter existing: The stored profile, or `nil` for an account that has none yet.
    static func plan(
        answers: PreAuthOnboardingAnswers,
        existing: UserDisplayNameData?,
        now: Date = Date()
    ) -> OnboardingProfileFill {
        var fill = OnboardingProfileFill()

        if existing?.birthday == nil, existing?.legacyAge == nil,
           let birthday = answers.birthday.flatMap(profileBirthday),
           let age = birthday.age(on: now),
           ProfileBirthday.validAgeRange.contains(age) {
            fill.birthday = birthday
        }

        if existing?.gender == nil {
            fill.gender = answers.gender
        }

        if existing?.weightKg == nil, let weight = answers.weightKg,
           weight > 0, weightKgRange.contains(weight) {
            fill.weightKg = weight
        }

        if existing?.heightCm == nil, let height = answers.heightCm,
           heightCmRange.contains(height) {
            fill.heightCm = height
        }

        if hasNoRealName(existing), let name = answers.writableName {
            fill.name = name
        }

        if existing?.profilePictureURL?.isEmpty ?? true, let photo = answers.profilePhotoFileName {
            fill.photoFileName = photo
        }

        let existingCity = existing?.locationCity?.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingCity?.isEmpty ?? true {
            fill.city = answers.city.flatMap(writableCity)
        }

        return fill
    }

    /// Whether the account has no name worth keeping: none at all, or a placeholder an earlier
    /// sign-in wrote when nobody supplied one. A profile that already carries a real name keeps it.
    private static func hasNoRealName(_ existing: UserDisplayNameData?) -> Bool {
        guard let existing else { return true }
        guard let resolved = existing.resolvedDisplayName else { return true }

        return resolved == SignInNamePlaceholder.boardName
    }

    private static func profileBirthday(_ birthday: PreAuthOnboardingBirthday) -> ProfileBirthday? {
        ProfileBirthday(
            rawValue: String(format: "%04d-%02d-%02d", birthday.year, birthday.month, birthday.day)
        )
    }

    /// The city as the rules will take it, or `nil` when its name or country cannot be written. A
    /// region is optional on a profile, so one the rules would refuse is left off rather than
    /// costing the climber their city.
    private static func writableCity(_ city: PreAuthOnboardingCity) -> PreAuthOnboardingCity? {
        let name = city.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = city.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard locationTextLength.contains(name.count),
              country.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil else {
            return nil
        }

        let region = city.region?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var writable = city
        writable.city = name
        writable.countryCode = country
        writable.region = locationTextLength.contains(region.count) ? region : nil
        return writable
    }
}

extension PreAuthOnboardingAnswers {
    /// Whether the climber gave an answer that belongs on a profile, a name the policy refuses
    /// included: the hand-off is what clears that from the device.
    var carriesProfileAnswers: Bool {
        carriesWritableProfileAnswers || firstName != nil || lastName != nil
    }

    /// Whether any answer will actually reach the profile.
    var carriesWritableProfileAnswers: Bool {
        birthday != nil || gender != nil || heightCm != nil || weightKg != nil || city != nil ||
            writableName != nil || profilePhotoFileName != nil
    }

    /// The typed name, when `DisplayNamePolicy` accepts the board name it makes. One half is a whole
    /// name; a name the policy refuses is left out rather than blocking the rest.
    var writableName: OnboardingProfileFill.Name? {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? DisplayNamePolicy.typedBoardName(firstName: first, lastName: last)) != nil else { return nil }

        return OnboardingProfileFill.Name(firstName: first, lastName: last)
    }

    /// Whether the answers themselves show work for the hand-off: one that belongs on a profile, the
    /// Health workouts found for the history import, or the usual climb, which only has to leave
    /// the device. The flow's own bookkeeping - when it ended - is not one, and neither
    /// is the days-a-week target, which the hand-off judges against the weekly-target service's copy.
    var carriesHandOffWork: Bool {
        carriesProfileAnswers || !foundHealthWorkoutIDs.isEmpty ||
            usualClimbSteps != nil || usualClimbMinutes != nil
    }

    /// What is left on the device once the profile has the answers. The days-a-week target stays
    /// because the weekly nudge reads it, and the Health workouts stay until the import lands them.
    var droppingHandedOffAnswers: PreAuthOnboardingAnswers {
        var kept = self
        kept.usualClimbSteps = nil
        kept.usualClimbMinutes = nil
        kept.firstName = nil
        kept.lastName = nil
        kept.profilePhotoFileName = nil
        kept.gender = nil
        kept.birthday = nil
        kept.heightCm = nil
        kept.weightKg = nil
        kept.city = nil
        return kept
    }
}
