import Foundation
import Testing
@testable import AscendApp

@MainActor
struct OnboardingAnalyticsEventTests {
    @Test
    func profileScreenCompletedUsesStableEventNameWithoutAnswerProperties() {
        let context = OnboardingAnalyticsContext(
            segmentID: "post_auth_onboarding",
            stepID: "gender"
        )

        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: context,
            inputType: "single_select",
            properties: [:]
        ).record

        #expect(record.name == "onboarding_screen_completed")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
        expectStringParameter(record, "flow_version", "v1")
        expectStringParameter(record, "step_id", "gender")
        expectStringParameter(record, "screen_id", "gender")
        expectStringParameter(record, "input_type", "single_select")
        expectBoolParameter(record, "completed", true)
        expectMissingParameter(record, "question_id")
        expectMissingParameter(record, "selection_type")
        expectMissingParameter(record, "answer_id")
        expectMissingParameter(record, "answer_index")
        expectMissingParameter(record, "has_answer")
    }

    @Test
    func surveyQuestionAnsweredUsesStableEventNameAndAnswerProperties() {
        let context = OnboardingAnalyticsContext(
            segmentID: "post_auth_onboarding",
            stepID: "stair_stepper_baseline"
        )

        let record = OnboardingAnalyticsEvent.questionAnswered(
            context: context,
            questionID: "stair_stepper_baseline",
            inputType: "single_select",
            selectionType: "single_select",
            answerID: "no_access",
            answerIndex: 0,
            properties: ["answer_count": .int(1)]
        ).record

        #expect(record.name == "onboarding_question_answered")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "stair_stepper_baseline")
        expectStringParameter(record, "screen_id", "stair_stepper_baseline")
        expectStringParameter(record, "question_id", "stair_stepper_baseline")
        expectStringParameter(record, "input_type", "single_select")
        expectStringParameter(record, "selection_type", "single_select")
        expectStringParameter(record, "answer_id", "no_access")
        expectIntParameter(record, "answer_index", 0)
        expectIntParameter(record, "answer_count", 1)
        expectBoolParameter(record, "has_answer", true)
    }

    @Test
    func authStartedUsesStableAuthContext() {
        let record = OnboardingAnalyticsEvent.authStarted(provider: "apple").record

        #expect(record.name == "onboarding_auth_started")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "pre_auth_auth")
        expectStringParameter(record, "step_id", "auth")
        expectStringParameter(record, "provider", "apple")
    }

    @Test
    func notificationPermissionSelectedUsesStatusAsSingleSelectAnswer() {
        let context = OnboardingAnalyticsContext(
            segmentID: "post_auth_onboarding",
            stepID: "notifications"
        )

        let record = OnboardingAnalyticsEvent.notificationPermissionSelected(
            context: context,
            status: "skip"
        ).record

        #expect(record.name == "onboarding_question_answered")
        expectStringParameter(record, "step_id", "notifications")
        expectStringParameter(record, "question_id", "notifications")
        expectStringParameter(record, "input_type", "permission_prompt")
        expectStringParameter(record, "selection_type", "single_select")
        expectStringParameter(record, "answer_id", "skip")
        expectStringParameter(record, "status", "skip")
    }

    @Test
    func onboardingPaywallReachedKeepsPlacementAndSource() {
        let record = OnboardingAnalyticsEvent.paywallReached(
            placement: "app_access_gate",
            source: "post_auth_onboarding"
        ).record

        #expect(record.name == "onboarding_paywall_reached")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "paywall")
        expectStringParameter(record, "placement", "app_access_gate")
        expectStringParameter(record, "source", "post_auth_onboarding")
    }

    @Test
    func welcomeScreenViewedUsesUniqueWelcomeStep() {
        let record = OnboardingAnalyticsEvent.screenViewed(
            context: OnboardingAnalyticsEvent.welcomeContext
        ).record

        #expect(record.name == "onboarding_screen_viewed")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "pre_auth_welcome")
        expectStringParameter(record, "step_id", "welcome")
        expectStringParameter(record, "screen_id", "welcome")
        expectBoolParameter(record, "viewed", true)
    }

    @Test
    func welcomeScreenCompletedRecordsGetStartedTap() {
        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: OnboardingAnalyticsEvent.welcomeContext,
            inputType: "button",
            properties: ["action_id": .string("get_started")]
        ).record

        #expect(record.name == "onboarding_screen_completed")
        expectStringParameter(record, "step_id", "welcome")
        expectStringParameter(record, "input_type", "button")
        expectStringParameter(record, "action_id", "get_started")
        expectBoolParameter(record, "completed", true)
    }

    @Test
    func authScreenViewedUsesStableAuthContext() {
        let record = OnboardingAnalyticsEvent.screenViewed(
            context: OnboardingAnalyticsEvent.authContext
        ).record

        #expect(record.name == "onboarding_screen_viewed")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "pre_auth_auth")
        expectStringParameter(record, "step_id", "auth")
        expectStringParameter(record, "screen_id", "auth")
    }

    @Test
    func paywallScreenViewedKeepsItsOwnSegment() {
        let record = OnboardingAnalyticsEvent.screenViewed(
            context: OnboardingAnalyticsEvent.paywallContext
        ).record

        #expect(record.name == "onboarding_screen_viewed")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "paywall")
        expectStringParameter(record, "screen_id", "paywall")
        expectIntParameter(record, "step_index", 20)
    }

    @Test
    func flowStartedUsesStableEventName() {
        let record = OnboardingAnalyticsEvent.flowStarted(
            context: OnboardingAnalyticsEvent.welcomeContext,
            resume: false
        ).record

        #expect(record.name == "onboarding_flow_started")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "pre_auth_welcome")
        expectStringParameter(record, "step_id", "welcome")
        expectIntParameter(record, "step_index", 0)
        expectIntParameter(record, "step_count", 21)
        expectBoolParameter(record, "resume", false)
    }

    @Test
    func backTappedNamesTheStepBeingLeft() {
        let record = OnboardingAnalyticsEvent.backTapped(
            context: OnboardingAnalyticsContext(segmentID: "post_auth_onboarding", stepID: "gender"),
            inputType: "button"
        ).record

        #expect(record.name == "onboarding_back_tapped")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "gender")
        expectStringParameter(record, "from_step", "gender")
        expectStringParameter(record, "input_type", "button")
    }

}

private func expectStringParameter(_ record: TelemetryRecord, _ key: String, _ expected: String) {
    guard case .string(let actual)? = record.parameters[key] else {
        #expect(Bool(false), "Expected string telemetry parameter \(key)")
        return
    }

    #expect(actual == expected)
}

private func expectIntParameter(_ record: TelemetryRecord, _ key: String, _ expected: Int) {
    guard case .int(let actual)? = record.parameters[key] else {
        #expect(Bool(false), "Expected int telemetry parameter \(key)")
        return
    }

    #expect(actual == expected)
}

private func expectBoolParameter(_ record: TelemetryRecord, _ key: String, _ expected: Bool) {
    guard case .bool(let actual)? = record.parameters[key] else {
        #expect(Bool(false), "Expected bool telemetry parameter \(key)")
        return
    }

    #expect(actual == expected)
}

private func expectMissingParameter(_ record: TelemetryRecord, _ key: String) {
    #expect(record.parameters[key] == nil)
}
