import Foundation

/// One row of the sign-in screen's list: something that saves to the account the moment the
/// climber signs in, said in terms of what the flow actually collected.
struct OnboardingSavedItem: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Every climb from today on. Always.
        case climbs
        /// The Apple Health history the climber asked to bring in on 07a.
        case healthHistory
        /// The profile screen and the city, as far as they were filled in.
        case profile
        /// The leaderboards and live climbs. Always.
        case boards
    }

    let kind: Kind
    let title: String
    let subtitle: String
    /// What the mark says instead of its glyph: the profile row's initials, once a name was typed.
    var initials: String?
    /// The picture the mark draws instead of the initials or the glyph: the profile row's photo,
    /// once one was picked and while it is still on the device.
    var photoURL: URL?

    var id: Kind { kind }
}

/// Builds the list from the answers. A row for something the climber skipped is absent, never
/// shown as done: the list is a record of what they gave, not a promise of what they could have.
enum OnboardingSavedItems {
    /// - Parameter photoURL: where the picked photo is on the device, if there is one
    ///   (`OnboardingV3Coordinator.profilePhotoURL`); the answers only name its file.
    static func make(
        from answers: PreAuthOnboardingAnswers,
        photoURL: URL? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [OnboardingSavedItem] {
        var items = [climbs(answers)]
        if let history = healthHistory(answers) { items.append(history) }
        if let profile = profile(answers, photoURL: photoURL, now: now, calendar: calendar) { items.append(profile) }
        items.append(OnboardingSavedItem(
            kind: .boards,
            title: "Your spot on the boards",
            subtitle: "Leaderboards and live climbs"
        ))
        return items
    }

    private static func climbs(_ answers: PreAuthOnboardingAnswers) -> OnboardingSavedItem {
        var subtitle = "Steps, time, streak and new bests"
        if let target = answers.weeklyTargetDays.flatMap(WeeklyTarget.init(days:)) {
            subtitle += " \u{00B7} \(target.summary)"
        }
        return OnboardingSavedItem(kind: .climbs, title: "Every climb from today", subtitle: subtitle)
    }

    private static func healthHistory(_ answers: PreAuthOnboardingAnswers) -> OnboardingSavedItem? {
        let count = answers.foundHealthWorkoutIDs.count
        guard count > 0 else { return nil }

        var title = count == 1 ? "1 past climb" : "\(count.formatted()) past climbs"
        if let steps = answers.foundHealthKnownSteps {
            title += " \u{00B7} \(steps.formatted()) steps"
        }
        return OnboardingSavedItem(
            kind: .healthHistory,
            title: title,
            subtitle: "From Apple Health, with past bests"
        )
    }

    private static func profile(
        _ answers: PreAuthOnboardingAnswers,
        photoURL: URL?,
        now: Date,
        calendar: Calendar
    ) -> OnboardingSavedItem? {
        guard answers.carriesWritableProfileAnswers else { return nil }

        // `writableName` is what sign-in publishes, so a name the policy refuses is never said back.
        let nameParts = answers.writableName.map { [$0.firstName, $0.lastName].filter { !$0.isEmpty } } ?? []
        let name = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
        let age = answers.birthday.flatMap { ProfileSetupDraft.age(of: $0, on: now, calendar: calendar) }
        let parts = [name, genderLetter(answers.gender), age.map { $0.formatted() }].compactMap { $0 }
        let title = parts.isEmpty ? "Your details" : parts.joined(separator: " \u{00B7} ")

        var subtitle = "Your profile"
        if let city = answers.city?.city.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            subtitle += " \u{00B7} \(city)"
        }
        return OnboardingSavedItem(
            kind: .profile,
            title: title,
            subtitle: subtitle,
            initials: name == nil ? nil : ProfileSetupDraft.initials(of: nameParts),
            // A photo the answers name but the device no longer holds draws nothing: the row
            // falls back to the initials or the glyph, the way the profile would.
            photoURL: answers.profilePhotoFileName == nil ? nil : photoURL
        )
    }

    /// The letter the profile screen's Male and Female choices abbreviate to. The other two answers have no
    /// letter and say nothing in the title.
    private static func genderLetter(_ gender: ProfileGender?) -> String? {
        switch gender {
        case .man: "M"
        case .woman: "F"
        case .nonBinary, .preferNotToSay, nil: nil
        }
    }
}
