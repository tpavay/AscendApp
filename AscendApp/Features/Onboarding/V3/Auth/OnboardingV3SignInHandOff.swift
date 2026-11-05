import Foundation

/// A mark left on the device the moment a climber taps a sign-in provider at the end of the flow,
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

/// Everything that happens when a climber signs in at the end of the v3 flow, and the few things
/// that happen on any sign-in.
///
/// In order:
/// 1. If the flow was walked to its end, post-sign-in onboarding is marked complete. The flow
///    already asked those questions, and until this is marked the route would show the old ones.
/// 2. An anonymous purchase moves onto the account, whatever route led here - bought then signed in,
///    restored, the gift, or "Already climbing? Sign in" - and the purchase ledger is cleared
///    afterwards, because a signed-in climber has nothing left to resume.
/// 3. The answers the climber gave are written to the profile, filling blanks only, then the Health
///    history the climber asked for is imported, and the answers are dropped from the device. Health
///    authorization and the history read happened before sign-in; the import itself needs an
///    account, so it waits for this step. The ongoing import (`syncNow()`) is the authenticated
///    bootstrap's own work and is not started here.
///
/// Step 3 is the only one that writes a profile, and it sits behind
/// `onboarding_answers_profile_write_enabled`: switched off, the answers stay on the device exactly
/// as they were and the next run writes them.
@MainActor
final class OnboardingV3SignInHandOff {
    /// Everything the hand-off reaches outside itself, so each step and its order are tested without
    /// the network, RevenueCat or the Health store.
    struct Seams {
        /// Moves the anonymous purchase to the account and waits for the server grant.
        var completePurchaseTransfer: @MainActor () async -> Void
        /// Forgets the purchase the signed-out device was holding.
        var clearPurchaseLedger: @MainActor () -> Void
        var isProfileWriteEnabled: @MainActor () -> Bool
        var readProfile: @MainActor (_ userId: String) async throws -> UserDisplayNameData?
        var writeProfile: @MainActor (_ userId: String, _ email: String?, _ fill: OnboardingProfileFill) async throws -> Void
        /// Reports a profile read or write that failed for a reason time will not clear.
        var recordProfileStepFailure: @MainActor (_ error: any Error) -> Void
        /// Brings in the Health history the climber asked for on 07a. Runs only after the profile
        /// has the answers, and only when there were answers to carry.
        var importHealthHistory: @MainActor (_ answers: PreAuthOnboardingAnswers) async -> Void
        /// Marks post-sign-in onboarding complete for the signed-in climber.
        var markPostSignInOnboardingComplete: @MainActor () -> Void
        /// Saves the days-a-week target the climber chose on 10 to their account, through the
        /// weekly-target service, which keeps the device's copy and owns its own kill switch.
        var saveWeeklyTarget: @MainActor (_ userId: String, _ days: Int) async -> Void
        /// The target the account holds, in days, or `nil` when it has none. Reads the profile,
        /// never the device-only copy: sign-out erases that copy, and the account is what carries
        /// a target back onto this phone.
        var readWeeklyTarget: @MainActor (_ userId: String) async -> Int?
        /// Hands the target to the local reminder scheduler, which replaces the weekly-target
        /// reminders to match it and this week's climbs; `nil` clears them.
        var reconcileWeeklyReminder: @MainActor (_ targetDays: Int?) async -> Void
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

        await seams.completePurchaseTransfer()
        seams.clearPurchaseLedger()

        let outcome = await writeAnswersIfAny(userId: userId, email: email)
        await restoreWeeklyReminder(userId: userId)
        return outcome
    }

    /// Puts the weekly reminder back from the account's target. Sign-out erases the device-only
    /// copy of the target, so without this a climber who signs out and back in, or signs in on a
    /// new phone, stops being reminded: the reminder would wait for a target nothing restores.
    /// Runs on every sign-in, returning mode included, because it reads the account rather than
    /// the answers.
    private func restoreWeeklyReminder(userId: String) async {
        let days = await seams.readWeeklyTarget(userId)
        await seams.reconcileWeeklyReminder(days)
    }

    /// Runs on launch and foreground for a climber who is already signed in, to land answers a
    /// failed or switched-off write left behind. Moves no purchase.
    @discardableResult
    func retryPendingAnswers(userId: String, email: String?) async -> Outcome {
        let hadTarget = store.answers().weeklyTargetDays != nil
        let outcome = await writeAnswersIfAny(userId: userId, email: email)
        // A target that only now reached the account is a reminder that only now can be set.
        if hadTarget, outcome == .complete {
            await restoreWeeklyReminder(userId: userId)
        }
        return outcome
    }

    private func writeAnswersIfAny(userId: String, email: String?) async -> Outcome {
        let answers = store.answers()
        guard answers.carriesHandOffWork else { return .complete }
        guard seams.isProfileWriteEnabled(), !isRunningProfileStep else { return .deferred }

        isRunningProfileStep = true
        defer { isRunningProfileStep = false }

        do {
            let existing = try await seams.readProfile(userId)
            let fill = OnboardingProfileFill.plan(answers: answers, existing: existing)
            if !fill.isEmpty {
                try await seams.writeProfile(userId, email, fill)
            }
        } catch {
            if Self.isWorthReporting(error) {
                seams.recordProfileStepFailure(error)
            }
            return .deferred
        }

        // The service keeps a target it could not send and sends it later, so a refusal here is
        // not a reason to hold the other answers.
        if let days = answers.weeklyTargetDays {
            await seams.saveWeeklyTarget(userId, days)
        }

        await seams.importHealthHistory(answers)
        store.update { $0 = $0.droppingHandedOffAnswers }
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
    /// The purchase, Health and weekly-target seams are left empty here on purpose: the purchase
    /// transfer (`PreAuthPurchaseTransfer.completeAfterSignIn()`) and its ledger belong to the
    /// paywall chunk, `WeeklyTargetService` and the profile's `weekly_target_days` to the setup
    /// chunk, and `LocalReminderScheduler.reconcileWeeklyTarget` to the notifications chunk, none
    /// of which has reached this branch. Chunk H wires them in these closures when the chunks
    /// meet; `OnboardingAuthTests` pins that every route calls them, in order.
    static func live(
        markPostSignInOnboardingComplete: @escaping @MainActor () -> Void,
        completePurchaseTransfer: @escaping @MainActor () async -> Void = {},
        clearPurchaseLedger: @escaping @MainActor () -> Void = {},
        importHealthHistory: @escaping @MainActor (PreAuthOnboardingAnswers) async -> Void = { _ in },
        saveWeeklyTarget: @escaping @MainActor (String, Int) async -> Void = { _, _ in },
        readWeeklyTarget: @escaping @MainActor (String) async -> Int? = { _ in nil },
        reconcileWeeklyReminder: @escaping @MainActor (Int?) async -> Void = { _ in }
    ) -> OnboardingV3SignInHandOff {
        OnboardingV3SignInHandOff(
            seams: Seams(
                completePurchaseTransfer: completePurchaseTransfer,
                clearPurchaseLedger: clearPurchaseLedger,
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
                saveWeeklyTarget: saveWeeklyTarget,
                readWeeklyTarget: readWeeklyTarget,
                reconcileWeeklyReminder: reconcileWeeklyReminder
            )
        )
    }
}
