import Foundation
import Testing
import UserNotifications
@testable import AscendApp

/// What a v3 climber leaves behind in analytics beyond the one view each step reports: how each step
/// was left, where it led, the answers the setup screens collect, the email box, and the sign-in
/// events' own context. Every assertion reads a real emission through a sink.
@MainActor
struct OnboardingV3StepAnalyticsTests {
    private struct Rig {
        let sink: InMemoryTelemetrySink
        let telemetry: TelemetryManager
        let coordinator: OnboardingV3Coordinator

        func records(_ name: String) -> [EnvelopedTelemetryRecord] {
            sink.records.filter { $0.name == name }
        }

        var names: [String] { sink.records.map(\.name) }
    }

    private func rig(at step: OnboardingV3Step = .welcome, tweak: (inout PreAuthOnboardingAnswers) -> Void = { _ in }) -> Rig {
        let suite = "onboarding-v3-step-analytics-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.update(tweak)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let coordinator = OnboardingV3Coordinator(
            store: store,
            startingAt: step,
            now: everyTapAfterTheTransition(),
            telemetry: telemetry
        )
        return Rig(sink: sink, telemetry: telemetry, coordinator: coordinator)
    }

    // MARK: - Completed

    @Test
    func leavingAStepReportsHowAndWhereToUnderTheV3Context() throws {
        let rig = rig(at: .goHarder)

        rig.coordinator.advance()

        let completed = try #require(rig.records("onboarding_screen_completed").first)
        #expect(completed.parameters["action_id"] == .string("continue"))
        #expect(completed.parameters["next_step_id"] == .string("get_better"))
        #expect(completed.parameters["input_type"] == .string("button"))
        #expect(completed.parameters["completed"] == .bool(true))
        #expect(completed.parameters["flow_version"] == .string("v3"))
        #expect(completed.parameters["segment_id"] == .string("onboarding_v3"))
        #expect(completed.parameters["step_id"] == .string("go_harder"))
        #expect(completed.parameters["step_index"] == .int(1))
        #expect(completed.parameters["step_count"] == .int(15))
        // The view stays the funnel's, reported by the screen modifier and not by this move.
        #expect(rig.records("onboarding_screen_viewed").isEmpty)
    }

    @Test
    func theSignInShortcutOnWelcomeIsNamedForWhatItIs() throws {
        let rig = rig(at: .welcome)

        rig.coordinator.go(to: .auth)

        let completed = try #require(rig.records("onboarding_screen_completed").first)
        #expect(completed.parameters["action_id"] == .string("already_have_account"))
        #expect(completed.parameters["next_step_id"] == .string("auth"))
    }

    @Test
    func healthSkipAndHealthWithNothingFoundAreTwoDifferentExits() throws {
        let skip = rig(at: .healthConnect)
        OnboardingHealthConnectScreen.declineHealth(skip.coordinator)
        #expect(skip.records("onboarding_screen_completed").first?.parameters["action_id"] == .string("skip"))
        #expect(skip.records("onboarding_screen_completed").first?.parameters["next_step_id"] == .string("usual_climb"))

        let connect = rig(at: .healthConnect)
        connect.coordinator.advance()
        #expect(connect.records("onboarding_screen_completed").first?.parameters["action_id"] == .string("continue"))
        #expect(connect.records("onboarding_screen_completed").first?.parameters["next_step_id"] == .string("health_permission"))

        let none = rig(at: .healthPermission)
        none.coordinator.go(to: .usualClimb)
        #expect(none.records("onboarding_screen_completed").first?.parameters["action_id"] == .string("no_workouts_found"))
    }

    @Test
    func aSwallowedDoubleTapReportsNothing() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let suite = "onboarding-v3-double-tap-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let frozen = ContinuousClock.now
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .goHarder,
            now: { frozen },
            telemetry: telemetry
        )

        coordinator.advance()
        coordinator.advance()

        #expect(sink.records.filter { $0.name == "onboarding_screen_completed" }.count == 1)
    }

    // MARK: - Back

    @Test
    func backReportsTheTapAndWhereItLedWithoutCountingACompletion() throws {
        let rig = rig(at: .goHarder)
        rig.coordinator.advance()
        rig.coordinator.back()

        let backs = rig.records("onboarding_back_tapped")
        #expect(backs.count == 1)
        #expect(backs.first?.parameters["from_step"] == .string("get_better"))
        #expect(backs.first?.parameters["input_type"] == .string("button"))
        #expect(backs.first?.parameters["flow_version"] == .string("v3"))

        let completed = rig.records("onboarding_screen_completed")
        #expect(completed.count == 2)
        let retreat = try #require(completed.last)
        #expect(retreat.parameters["action_id"] == .string("back"))
        #expect(retreat.parameters["next_step_id"] == .string("go_harder"))
        #expect(retreat.parameters["completed"] == .bool(false))
    }

    @Test
    func backOnTheFirstScreenReportsNothing() {
        let rig = rig(at: .welcome)

        rig.coordinator.back()

        #expect(rig.sink.records.isEmpty)
    }

    // MARK: - Answers

    @Test
    func theUsualClimbAnswerIsTheBandAndNeverTheSteps() throws {
        let band = UsualClimbChoice.fifteenToThirty
        let rig = rig(at: .usualClimb) {
            $0.usualClimbSteps = band.steps
            $0.usualClimbMinutes = band.minutes
        }

        rig.coordinator.advance()

        let answer = try #require(rig.records("onboarding_question_answered").first)
        #expect(answer.parameters["question_id"] == .string("usual_climb"))
        #expect(answer.parameters["answer_id"] == .string("15_to_30"))
        #expect(answer.parameters["step_id"] == .string("usual_climb"))
        #expect(answer.parameters["flow_version"] == .string("v3"))
    }

    @Test
    func aUsualClimbReadFromHealthIsToldApartFromAPickedBand() throws {
        let rig = rig(at: .usualClimb) {
            $0.usualClimbSteps = 2_345
            $0.usualClimbMinutes = 31
        }

        rig.coordinator.advance()

        #expect(rig.records("onboarding_question_answered").first?.parameters["answer_id"] == .string("from_health"))
    }

    @Test
    func theProfileScreenReportsWhichFieldsWereFilledAndNeverTheirValues() throws {
        let rig = rig(at: .profileSetup) {
            $0.firstName = "Sam"
            $0.heightCm = 180
            $0.weightKg = 80
        }

        rig.coordinator.advance()

        let answer = try #require(rig.records("onboarding_question_answered").first)
        #expect(answer.parameters["question_id"] == .string("climber_card"))
        #expect(answer.parameters["answer_id"] == .string("filled"))
        #expect(answer.parameters["has_name"] == .bool(true))
        #expect(answer.parameters["has_height"] == .bool(true))
        #expect(answer.parameters["has_weight"] == .bool(true))
        #expect(answer.parameters["has_photo"] == .bool(false))
        #expect(answer.parameters["has_birthday"] == .bool(false))
        #expect(answer.parameters["has_gender"] == .bool(false))
        let valueText = answer.parameters.values.compactMap { value -> String? in
            if case .string(let text) = value { text } else { nil }
        }
        #expect(!valueText.contains("Sam"))
    }

    @Test
    func skippingTheProfileScreenIsASkipWithEveryFieldEmpty() throws {
        let rig = rig(at: .profileSetup)

        OnboardingProfileSetupScreen.skip(
            rig.coordinator,
            photos: OnboardingProfilePhotoStore(
                directory: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            )
        )

        let answer = try #require(rig.records("onboarding_question_answered").first)
        #expect(answer.parameters["answer_id"] == .string("skipped"))
        #expect(answer.parameters["has_name"] == .bool(false))
        #expect(rig.records("onboarding_screen_completed").first?.parameters["action_id"] == .string("skip"))
    }

    @Test
    func theCityIsClaimedOrSkippedAndNeverNamed() throws {
        let claimed = rig(at: .claimCity) {
            $0.city = PreAuthOnboardingCity(
                city: "Springfield",
                region: "IL",
                countryCode: "US",
                countryName: "United States"
            )
        }
        claimed.coordinator.advance()
        let claimedAnswer = try #require(claimed.records("onboarding_question_answered").first)
        #expect(claimedAnswer.parameters["question_id"] == .string("claim_city"))
        #expect(claimedAnswer.parameters["answer_id"] == .string("claimed"))
        #expect(!claimedAnswer.parameters.values.contains(.string("Springfield")))

        let skipped = rig(at: .claimCity)
        OnboardingClaimCityScreen.skip(skipped.coordinator)
        #expect(skipped.records("onboarding_question_answered").first?.parameters["answer_id"] == .string("skipped"))
        #expect(skipped.records("onboarding_screen_completed").first?.parameters["action_id"] == .string("skip"))
    }

    @Test
    func theWeeklyTargetIsTheNumberOfDaysOrASkip() throws {
        let set = rig(at: .weeklyTarget) { $0.weeklyTargetDays = 4 }
        set.coordinator.advance()
        let answer = try #require(set.records("onboarding_question_answered").first)
        #expect(answer.parameters["question_id"] == .string("weekly_target"))
        #expect(answer.parameters["answer_id"] == .string("4"))
        #expect(answer.parameters["target_days"] == .int(4))

        let skipped = rig(at: .weeklyTarget) { $0.weeklyTargetDays = 4 }
        OnboardingWeeklyTargetScreen.skip(skipped.coordinator)
        #expect(skipped.records("onboarding_question_answered").first?.parameters["answer_id"] == .string("skipped"))
        #expect(skipped.records("onboarding_question_answered").first?.parameters["target_days"] == nil)
    }

    @Test
    func aBackMoveReportsNoAnswer() {
        let rig = rig(at: .claimCity)

        rig.coordinator.back()
        #expect(rig.records("onboarding_question_answered").isEmpty)
    }

    @Test
    func healthPermissionReportsWhatTheSheetAndTheReadCameTo() async throws {
        let none = try await healthPermissionAnswers(grants: true, workouts: 0)
        #expect(none == ["none_found"])

        let found = try await healthPermissionAnswers(grants: true, workouts: 1)
        #expect(found == ["history_found"])

        let refused = try await healthPermissionAnswers(grants: false, workouts: 0)
        #expect(refused == ["request_failed"])
    }

    private func healthPermissionAnswers(grants: Bool, workouts: Int) async throws -> [String] {
        let harness = try AppleHealthImportHarness()
        harness.authorization.grantsAuthorization = grants
        if !grants { harness.authorization.lastPermissionErrorMessage = "Health said no." }
        for _ in 0..<workouts { harness.addWorkout(daysAgo: 100, steps: 3_000) }
        let connect = AppleHealthConnectViewModel(authorization: harness.authorization, importService: harness.service)
        let viewModel = OnboardingHealthPermissionViewModel(connect: connect, reader: harness.reader)
        let rig = rig(at: .healthPermission)

        await viewModel.gotIt(coordinator: rig.coordinator)

        return rig.records("onboarding_question_answered").compactMap { record in
            guard record.parameters["question_id"] == .string("health_permission"),
                  case .string(let id) = record.parameters["answer_id"] else { return nil }
            return id
        }
    }

    // MARK: - Email box

    private final class PropertyRecordingSink: TelemetrySink, @unchecked Sendable {
        let supportedDestinations: Set<TelemetryDestination> = [.analytics]
        private let lock = NSLock()
        private var storedRecords: [EnvelopedTelemetryRecord] = []
        private var storedProperties: [String: String] = [:]

        var records: [EnvelopedTelemetryRecord] { lock.withLock { storedRecords } }
        var properties: [String: String] { lock.withLock { storedProperties } }

        func setCollectionEnabled(_ enabled: Bool) {}
        func setUserID(_ userID: String?) {}
        func setUserProperty(_ name: String, value: String?) {
            lock.withLock { storedProperties[name] = value }
        }
        func record(_ record: EnvelopedTelemetryRecord) { lock.withLock { storedRecords.append(record) } }
        func record(screen: EnvelopedTelemetryScreen) {}
    }

    private func primer(emailTicked: Bool, status: UNAuthorizationStatus, turnOn: Bool) async throws -> PropertyRecordingSink {
        let suite = "onboarding-v3-primer-analytics-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let sink = PropertyRecordingSink()
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer,
            now: everyTapAfterTheTransition(),
            telemetry: telemetry
        )
        let model = NotificationPrimerViewModel(
            coordinator: coordinator,
            requestAuthorization: { status },
            declineNotifications: {},
            telemetry: telemetry
        )
        if model.emailOptIn != emailTicked { model.toggleEmailOptIn() }

        if turnOn { await model.turnOn() } else { await model.notNow() }
        return sink
    }

    @Test(arguments: [true, false])
    func theEmailBoxIsRecordedBesideThePushAnswerWhicheverButtonLeaves(ticked: Bool) async throws {
        let sink = try await primer(emailTicked: ticked, status: .authorized, turnOn: true)

        let answer = try #require(sink.records.first {
            $0.name == "onboarding_question_answered" && $0.parameters["question_id"] == .string("notifications")
        })
        #expect(answer.parameters["email_opt_in"] == .bool(ticked))
        #expect(answer.parameters["answer_id"] == .string("allow"))
        #expect(answer.parameters["flow_version"] == .string("v3"))
        #expect(sink.properties["email_opt_in"] == (ticked ? "true" : "false"))
        #expect(sink.properties["notifications_choice"] == "allow")
    }

    @Test
    func notNowStillRecordsATickedEmailBox() async throws {
        let sink = try await primer(emailTicked: true, status: .authorized, turnOn: false)

        let answer = try #require(sink.records.first { $0.name == "onboarding_question_answered" })
        #expect(answer.parameters["answer_id"] == .string("skip"))
        #expect(answer.parameters["email_opt_in"] == .bool(true))
        #expect(sink.properties["email_opt_in"] == "true")
        // The primer's leaving move reports the completion with the skip as its action.
        #expect(sink.records.contains {
            $0.name == "onboarding_screen_completed" && $0.parameters["action_id"] == .string("skip")
        })
    }

    @Test
    func theV1NotificationsAnswerCarriesNoEmailProperty() {
        let record = OnboardingAnalyticsEvent.notificationPermissionSelected(
            context: OnboardingAnalyticsContext(segmentID: "post_auth_onboarding", stepID: "notifications"),
            status: "allow"
        ).record

        #expect(record.parameters["email_opt_in"] == nil)
    }

    // MARK: - Sign-in context

    @Test
    func aV3SignInIsStampedWithTheV3FlowAtTheAuthStep() {
        let rig = rig(at: .auth)
        let context = rig.coordinator.analyticsContext

        for event: OnboardingAnalyticsEvent in [
            .authStarted(provider: "apple", context: context, entry: "walkthrough"),
            .authCompleted(provider: "apple", context: context, entry: "walkthrough"),
            .authFailed(provider: "apple", reason: "cancelled", context: context, entry: "walkthrough")
        ] {
            let record = event.record
            #expect(record.parameters["flow_version"] == .string("v3"))
            #expect(record.parameters["segment_id"] == .string("onboarding_v3"))
            #expect(record.parameters["step_id"] == .string("auth"))
            #expect(record.parameters["step_index"] == .int(14))
            #expect(record.parameters["step_count"] == .int(15))
            #expect(record.parameters["entry"] == .string("walkthrough"))
            #expect(record.parameters["provider"] == .string("apple"))
        }
    }

    @Test
    func aV1SignInKeepsEveryValueItAlwaysHad() {
        let record = OnboardingAnalyticsEvent.authCompleted(provider: "google").record

        #expect(record.parameters["flow_version"] == .string("v1"))
        #expect(record.parameters["segment_id"] == .string("pre_auth_auth"))
        #expect(record.parameters["step_index"] == .int(3))
        #expect(record.parameters["step_count"] == .int(21))
        #expect(record.parameters["entry"] == nil)
    }

    @Test
    func theReturningShortcutAndTheWalkthroughAreToldApart() {
        #expect(OnboardingAuthMode(arrivedFrom: .welcome).analyticsEntry == "welcome_shortcut")
        #expect(OnboardingAuthMode(arrivedFrom: .notificationPrimer).analyticsEntry == "walkthrough")
        #expect(OnboardingAuthMode(arrivedFrom: nil).analyticsEntry == "walkthrough")
    }
}
