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

    var isEmpty: Bool {
        birthday == nil && gender == nil && weightKg == nil && heightCm == nil && city == nil
    }

    /// The bounds `firestore.rules` and the profile editors share.
    static let weightKgRange = 0.0...400.0
    static let heightCmRange = 90.0...240.0

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

        let existingCity = existing?.locationCity?.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingCity?.isEmpty ?? true, let city = answers.city, isWritable(city) {
            fill.city = city
        }

        return fill
    }

    private static func profileBirthday(_ birthday: PreAuthOnboardingBirthday) -> ProfileBirthday? {
        ProfileBirthday(
            rawValue: String(format: "%04d-%02d-%02d", birthday.year, birthday.month, birthday.day)
        )
    }

    private static func isWritable(_ city: PreAuthOnboardingCity) -> Bool {
        let name = city.city.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 120 && city.countryCode.count == 2
    }
}

extension PreAuthOnboardingAnswers {
    /// Whether the climber gave an answer the hand-off still has to deliver: one that belongs on a
    /// profile, the Health workouts found for the history import, or the days-a-week target. The flow's own bookkeeping -
    /// when it ended, whether a trial started - is not one.
    var carriesHandOffWork: Bool {
        birthday != nil || gender != nil || heightCm != nil || weightKg != nil || city != nil ||
            !foundHealthWorkoutIDs.isEmpty || weeklyTargetDays != nil
    }

    /// The same answers with everything personal dropped and the flow's bookkeeping kept, which is
    /// what is left on the device once the profile has them and the history has been imported.
    var droppingHandedOffAnswers: PreAuthOnboardingAnswers {
        var kept = self
        kept.foundHealthWorkoutIDs = []
        kept.weeklyTargetDays = nil
        kept.gender = nil
        kept.birthday = nil
        kept.heightCm = nil
        kept.weightKg = nil
        kept.city = nil
        return kept
    }
}
