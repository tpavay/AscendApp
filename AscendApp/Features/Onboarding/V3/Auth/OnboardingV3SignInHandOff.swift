import Foundation

/// A mark left on the device the moment a climber taps a sign-in provider after the setup screens,
/// so the root can tell, the instant the account appears, that this sign-in closes the flow.
///
/// It exists because the account appears before the sign-in call returns, and the root routes on
/// the account: a mark written after the call would arrive after the route had already sent a
/// climber who just answered every question into the old post-sign-in questions.
struct OnboardingV3HandOffIntent: @unchecked Sendable {
    static let storageKey = "onboardingV3.handOffIntent"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isSet: Bool { userDefaults.bool(forKey: Self.storageKey) }

    func set() { userDefaults.set(true, forKey: Self.storageKey) }

    func clear() { userDefaults.removeObject(forKey: Self.storageKey) }
}

/// Everything that happens when a climber signs in after the v3 setup screens, and the few things
/// that happen on any sign-in.
///
/// In order:
/// 1. If the flow was walked to its end, post-sign-in onboarding is marked complete. The flow
///    already asked those questions, and until this is marked the route would show the old ones.
/// 2. The answers the climber gave are written to the profile, filling blanks only, then a
///    days-a-week target the account does not have yet is saved, the Health history the climber
///    asked for is imported, and the delivered answers are dropped from the device. Health
///    authorization and the history read happened before sign-in; the import itself needs an
///    account and its cloud restore, so it waits for this step and, when the restore has not
///    confirmed yet, for the authenticated bootstrap to run this again once it has. The ongoing
///    import (`syncNow()`) is the authenticated bootstrap's own work and is not started here.
/// 3. The device and the account agree on the target, which is what puts the weekly reminder back.
///
/// Nothing here touches a purchase. Sign-in comes before the paywall, so every purchase is made by
/// the account that signed in, and a climber who already pays is recognised by the entitlement the
/// root reads and goes straight to the app.
///
/// Step 2 is the only one that writes a profile, and it sits behind
/// `onboarding_answers_profile_write_enabled`: switched off, the answers stay on the device exactly
/// as they were and the next run writes them. They leave the device early only when the climber
/// signs out, because the next account on this phone must not receive them
/// (`OnboardingV3Coordinator.sessionEnded()`).
@MainActor
final class OnboardingV3SignInHandOff {
    /// Everything the hand-off reaches outside itself, so each step and its order are tested without
    /// the network, RevenueCat or the Health store.
    struct Seams {
        var isProfileWriteEnabled: @MainActor () -> Bool
        /// Returns once this sign-in has resolved the account's name. The fill is planned after it,
        /// so a typed name lands on an account that resolution left without one, or over a
        /// placeholder already there, and a name the account already carried wins every time.
        var signInNameSettled: @MainActor () async -> Void
        var readProfile: @MainActor (_ userId: String) async throws -> UserDisplayNameData?
        var writeProfile: @MainActor (_ userId: String, _ email: String?, _ fill: OnboardingProfileFill) async throws -> Void
        /// Reports a profile read or write that failed for a reason time will not clear.
        var recordProfileStepFailure: @MainActor (_ error: any Error) -> Void
        /// Brings in the Health history the climber asked for on 07a. Runs only after the profile
        /// has the answers, and only when there were answers to carry. Returns whether the history
        /// landed; the workouts it found stay on the device until it does.
        var importHealthHistory: @MainActor (_ answers: PreAuthOnboardingAnswers) async -> Bool
        /// Marks post-sign-in onboarding complete for the signed-in climber and ends the flow.
        var markPostSignInOnboardingComplete: @MainActor () -> Void
        /// The signed-in climber's target in the weekly-target service's device copy, in days. A
        /// copy here means the service already owns delivering it to the account.
        var deviceWeeklyTarget: @MainActor (_ userId: String) -> Int?
        /// Saves the days-a-week target the climber chose on 10 to their account, through the
        /// weekly-target service, which keeps the device's copy and owns its own kill switch.
        var saveWeeklyTarget: @MainActor (_ userId: String, _ days: Int) async -> Void
        /// Brings the device and the account together through the weekly-target service, which
        /// tells the reminder coordinator the target that results. Sign-out clears what the nudge
        /// reads, and the account is what carries a target back onto this phone.
        var reconcileWeeklyTarget: @MainActor (_ userId: String) async -> Void
    }

    /// The account the answers were read for is no longer the signed-in one.
    struct SessionEnded: Error {}

    enum Outcome: Equatable {
        /// The profile has the answers, or there were none to write.
        case complete
        /// A write was refused or unreachable, or the switch is off. The answers are still on the
        /// device and the next run tries again.
        case deferred
    }

    private let seams: Seams
    private let store: PreAuthOnboardingStore
    private let intent: OnboardingV3HandOffIntent
    private let photos: OnboardingProfilePhotoStore
    private var isRunningProfileStep = false

    init(
        seams: Seams,
        store: PreAuthOnboardingStore = PreAuthOnboardingStore(),
        intent: OnboardingV3HandOffIntent = OnboardingV3HandOffIntent(),
        photos: OnboardingProfilePhotoStore = OnboardingProfilePhotoStore()
    ) {
        self.seams = seams
        self.store = store
        self.intent = intent
        self.photos = photos
    }

    /// Closes post-sign-in onboarding when this sign-in came from the end of the flow. Synchronous
    /// and idempotent, and called by the root in the same turn the account appears: anything that
    /// waits for an `await` first would let the route show the old questions for a moment.
    func closeFlowIfIntended() {
        guard intent.isSet else { return }

        seams.markPostSignInOnboardingComplete()
        intent.clear()
    }

    /// Runs on the sign-in itself: the account has just appeared.
    @discardableResult
    func runAfterSignIn(userId: String, email: String?) async -> Outcome {
        closeFlowIfIntended()

        let outcome = await writeAnswersIfAny(userId: userId, email: email)
        await seams.reconcileWeeklyTarget(userId)
        return outcome
    }

    /// Runs on launch and foreground for a climber who is already signed in, to land answers a
    /// failed or switched-off write left behind.
    @discardableResult
    func retryPendingAnswers(userId: String, email: String?) async -> Outcome {
        let hadUndeliveredTarget = undeliveredWeeklyTarget(in: store.answers(), userId: userId) != nil
        let outcome = await writeAnswersIfAny(userId: userId, email: email)
        // A target that only now reached the account is a reminder that only now can be set.
        if hadUndeliveredTarget, outcome == .complete {
            await seams.reconcileWeeklyTarget(userId)
        }
        return outcome
    }

    /// The target chosen before sign-in that nothing has delivered yet. The answer alone cannot say:
    /// it is also the record the weekly nudge reads, which Settings and Home keep true to the
    /// service's copy, so a value with a copy behind it is a live target, not hand-off work.
    private func undeliveredWeeklyTarget(in answers: PreAuthOnboardingAnswers, userId: String) -> Int? {
        seams.deviceWeeklyTarget(userId) == nil ? answers.weeklyTargetDays : nil
    }

    private func writeAnswersIfAny(userId: String, email: String?) async -> Outcome {
        let answers = store.answers()
        let target = undeliveredWeeklyTarget(in: answers, userId: userId)
        guard answers.carriesHandOffWork || target != nil else { return .complete }
        guard seams.isProfileWriteEnabled(), !isRunningProfileStep else { return .deferred }

        isRunningProfileStep = true
        defer { isRunningProfileStep = false }

        var accountHasTarget = false
        do {
            if answers.carriesProfileAnswers || target != nil {
                await seams.signInNameSettled()
                let existing = try await seams.readProfile(userId)
                let fill = OnboardingProfileFill.plan(answers: answers, existing: existing)
                if !fill.isEmpty {
                    try await seams.writeProfile(userId, email, fill)
                }
                accountHasTarget = existing?.weeklyTarget != nil
            }
        } catch {
            if Self.isWorthReporting(error) {
                seams.recordProfileStepFailure(error)
            }
            return .deferred
        }

        // The service keeps a target it could not send and sends it later, so a refusal here is
        // not a reason to hold the other answers.
        if let target, !accountHasTarget {
            await seams.saveWeeklyTarget(userId, target)
        }

        let imported = await seams.importHealthHistory(answers)
        store.update {
            $0 = $0.droppingHandedOffAnswers
            if imported { $0.clearFoundHealthHistory() }
        }
        // The picked photo has been uploaded, or the account already had one. Either way it is
        // done with the device.
        photos.remove()
        return .complete
    }

    /// No connection and a paused publish both clear on their own and the next run lands the
    /// answers. A refusal or anything unexpected repeats on every foreground until someone sees it,
    /// and neither caller shows the climber anything.
    private static func isWorthReporting(_ error: any Error) -> Bool {
        !(error is ProfilePublicationError) && !(error is SessionEnded) && ServerReadFailureClass.classify(error) != .unreachable
    }
}

// MARK: - Live wiring

extension OnboardingV3SignInHandOff {
    /// Writes a fill through the services the rest of the app uses: demographics, then the typed
    /// name, then the photo. Each lands on its own, so a photo that cannot upload yet leaves the
    /// name and demographics written; the retry plans from the profile as it now stands and carries
    /// only what is still missing. The session hears about a name and a photo as each lands, so the
    /// screens that read it show them without a relaunch.
    @MainActor
    static func writeProfile(
        _ fill: OnboardingProfileFill,
        userId: String,
        email: String?,
        session: AuthenticationViewModel,
        photos: OnboardingProfilePhotoStore = OnboardingProfilePhotoStore()
    ) async throws {
        func requireSameSession() throws {
            guard session.user?.uid == userId else { throw SessionEnded() }
        }

        try requireSameSession()

        if fill.hasDemographics {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: userId,
                email: email,
                birthday: fill.birthday,
                gender: fill.gender,
                weightKg: fill.weightKg,
                heightCm: fill.heightCm,
                locationCity: fill.city?.city,
                locationCountry: fill.city?.countryCode,
                locationRegion: fill.city?.region
            )
        }

        if let name = fill.name {
            let boardName = try await UserDataRepository.shared.updateTypedProfileName(
                userId: userId,
                email: email,
                firstName: name.firstName,
                lastName: name.lastName
            )
            try requireSameSession()
            await session.adoptWrittenName(boardName)
        }

        // A photo that is no longer on the device cannot be retried, so it is skipped here and the
        // hand-off's cleanup drops the answer that named it.
        if let data = try photos.data(for: fill.photoFileName) {
            try ProfilePublicationError.requireConnection()

            let filename = "users/\(userId)/profile_pictures/\(UUID().uuidString).jpg"
            let uploadedURL = try await FirebasePhotoRepository().upload(data, filename: filename)
            try await UserDataRepository.shared.updateProfilePictureURL(
                userId: userId,
                profilePictureURL: uploadedURL.absoluteString
            )
            try requireSameSession()
            session.adoptWrittenProfilePicture(uploadedURL)
        }
    }
}

extension OnboardingV3SignInHandOff {
    /// The hand-off against the real services. `OnboardingAuthTests` pins that every route calls
    /// these seams, in order.
    static func live(
        session: AuthenticationViewModel,
        markPostSignInOnboardingComplete: @escaping @MainActor () -> Void,
        importHealthHistory: @escaping @MainActor (PreAuthOnboardingAnswers) async -> Bool
    ) -> OnboardingV3SignInHandOff {
        OnboardingV3SignInHandOff(
            seams: Seams(
                isProfileWriteEnabled: {
                    RemoteFeatureFlagStore.shared.isEnabled(.onboardingAnswersProfileWrite)
                },
                signInNameSettled: {
                    await session.profileLoadSettled()
                },
                readProfile: { userId in
                    try await UserDataRepository.shared.getUserFromFirestore(userId: userId)
                },
                writeProfile: { userId, email, fill in
                    try await Self.writeProfile(fill, userId: userId, email: email, session: session)
                },
                recordProfileStepFailure: { error in
                    TelemetryManager.shared.recordError(
                        error,
                        context: .firestore,
                        code: "onboarding_answers_profile_step_failed"
                    )
                },
                importHealthHistory: importHealthHistory,
                markPostSignInOnboardingComplete: markPostSignInOnboardingComplete,
                deviceWeeklyTarget: { userId in
                    WeeklyTargetService().localTarget(for: userId)?.days
                },
                saveWeeklyTarget: { userId, days in
                    guard let target = WeeklyTarget(days: days) else { return }
                    await WeeklyTargetService().save(target, for: userId)
                },
                reconcileWeeklyTarget: { userId in
                    await WeeklyTargetService().reconcile(for: userId)
                }
            )
        )
    }
}
