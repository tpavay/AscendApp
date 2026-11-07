import Foundation

/// A calendar date of birth with no time or zone, so the age it gives never moves with the phone's
/// time zone.
struct PreAuthOnboardingBirthday: Codable, Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int
}

/// A city the climber picked, in the shape the post-sign-in profile write needs.
struct PreAuthOnboardingCity: Codable, Equatable, Sendable {
    var city: String
    var region: String?
    var countryCode: String
    var countryName: String

    init(city: String, region: String?, countryCode: String, countryName: String) {
        self.city = city
        self.region = region
        self.countryCode = countryCode
        self.countryName = countryName
    }

    init(_ selection: PostAuthLocationSelection) {
        self.init(
            city: selection.city,
            region: selection.region,
            countryCode: selection.countryCode,
            countryName: selection.countryName
        )
    }

    var selection: PostAuthLocationSelection {
        PostAuthLocationSelection(
            city: city,
            region: region,
            countryCode: countryCode,
            countryName: countryName
        )
    }
}

/// What the climber chose on the notification primer.
enum PreAuthOnboardingNotificationChoice: String, Codable, Equatable, Sendable {
    /// Turn on was tapped and iOS granted.
    case allowed
    /// Turn on was tapped and iOS declined.
    case denied
    /// Not now.
    case skipped
}

/// Everything the pre-sign-in flow collects. All optional: every screen can be skipped, and a
/// field nobody answered is simply absent.
///
/// Nothing here reaches Firestore. There is no uid until the sign-in step, so these answers wait on
/// the device and are written to the profile right after sign-in, never before.
struct PreAuthOnboardingAnswers: Codable, Equatable, Sendable {
    /// Steps and minutes of the climb the climber calls usual: typed in on `usual_climb`, or the
    /// median of the Health history on `health_history`.
    var usualClimbSteps: Int?
    var usualClimbMinutes: Int?

    var gender: ProfileGender?
    var birthday: PreAuthOnboardingBirthday?
    var heightCm: Double?
    var weightKg: Double?

    var city: PreAuthOnboardingCity?

    var weeklyTargetDays: Int?

    var notificationChoice: PreAuthOnboardingNotificationChoice?

    /// Identifiers of the stair stepper workouts the Health history read found, so the import that
    /// runs after sign-in does not read them a second time.
    var foundHealthWorkoutIDs: [String] = []

    /// The steps those workouts report between them, which the sign-in screen says back next to
    /// their count. Nil when none of them reported steps, and nothing without the identifiers:
    /// ``recordFoundHealthHistory(workoutIDs:knownSteps:)`` and ``clearFoundHealthHistory()`` keep
    /// the two together.
    var foundHealthKnownSteps: Int?

    /// When the climber reached the end of the flow. Present means the flow is finished and the
    /// app moves on to whatever follows it.
    var completedAt: Date?
}

extension PreAuthOnboardingAnswers {
    /// Records the history the climber asked to bring in on 07a: the workouts they were shown and
    /// the steps those workouts report.
    mutating func recordFoundHealthHistory(workoutIDs: [String], knownSteps: Int) {
        foundHealthWorkoutIDs = workoutIDs
        foundHealthKnownSteps = knownSteps > 0 ? knownSteps : nil
    }

    /// Leaves nothing to import: a no to Health, a read that found nothing, a history that landed,
    /// or a sign-out.
    mutating func clearFoundHealthHistory() {
        foundHealthWorkoutIDs = []
        foundHealthKnownSteps = nil
    }
}

/// The one place pre-sign-in answers live, grown from the older `PreAuthOnboardingSurveyStore`
/// that the post-sign-in flow still reads while the switch is off.
///
/// One JSON value under one key, so a screen never leaves the answers half written and an
/// undecodable value reads as "nothing answered" rather than failing the flow.
struct PreAuthOnboardingStore: @unchecked Sendable {
    static let storageKey = "preAuthOnboarding.v3.answers"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func answers() -> PreAuthOnboardingAnswers {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let answers = try? JSONDecoder().decode(PreAuthOnboardingAnswers.self, from: data) else {
            return PreAuthOnboardingAnswers()
        }

        return answers
    }

    func save(_ answers: PreAuthOnboardingAnswers) {
        guard let data = try? JSONEncoder().encode(answers) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    /// Reads, changes and writes back in one step, returning what was saved.
    @discardableResult
    func update(_ change: (inout PreAuthOnboardingAnswers) -> Void) -> PreAuthOnboardingAnswers {
        var answers = answers()
        change(&answers)
        save(answers)
        return answers
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}
