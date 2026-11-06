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
    private var isRunningProfileStep = false

    init(
        seams: Seams,
        store: PreAuthOnboardingStore = PreAuthOnboardingStore(),
        intent: OnboardingV3HandOffIntent = OnboardingV3HandOffIntent()
    ) {
        self.seams = seams
        self.store = store
        self.intent = intent
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
            if imported { $0.foundHealthWorkoutIDs = [] }
        }
        return .complete
    }

    /// No connection and a paused publish both clear on their own and the next run lands the
    /// answers. A refusal or anything unexpected repeats on every foreground until someone sees it,
    /// and neither caller shows the climber anything.
    private static func isWorthReporting(_ error: any Error) -> Bool {
        !(error is ProfilePublicationError) && ServerReadFailureClass.classify(error) != .unreachable
    }
}

// MARK: - Live wiring

extension OnboardingV3SignInHandOff {
    /// The hand-off against the real services.
    ///
    /// The Health seam is left empty here on purpose: the history import belongs to the Health
    /// chunk, and until it is wired it reports that nothing landed, so the workouts it found stay on
    /// the device. Chunk H wires it in this closure when the chunks meet; `OnboardingAuthTests` pins
    /// that every route calls these seams, in order.
    static func live(
        markPostSignInOnboardingComplete: @escaping @MainActor () -> Void,
        importHealthHistory: @escaping @MainActor (PreAuthOnboardingAnswers) async -> Bool = { _ in false }
    ) -> OnboardingV3SignInHandOff {
        OnboardingV3SignInHandOff(
            seams: Seams(
                isProfileWriteEnabled: {
                    RemoteFeatureFlagStore.shared.isEnabled(.onboardingAnswersProfileWrite)
                },
                readProfile: { userId in
                    try await UserDataRepository.shared.getUserFromFirestore(userId: userId)
                },
                writeProfile: { userId, email, fill in
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
