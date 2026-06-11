import Testing
@testable import AscendApp

struct OnboardingAnalyticsEventTests {
    @Test
    func stepViewedIncludesStableFunnelContext() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "experience",
            stepIndex: 1,
            stepCount: 5
        )

        let record = OnboardingAnalyticsEvent.stepViewed(context: context).record

        #expect(record.name == "onboarding_step_viewed")
        #expect(record.parameters["flow_id"] == .string("post_auth_onboarding"))
        #expect(record.parameters["flow_version"] == .string("v1"))
        #expect(record.parameters["step_id"] == .string("experience"))
        #expect(record.parameters["step_index"] == .int(1))
        #expect(record.parameters["step_count"] == .int(5))
    }

    @Test
    func answerSelectedUsesStableQuestionAndAnswerIDs() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "experience",
            stepIndex: 1,
            stepCount: 5
        )

        let record = OnboardingAnalyticsEvent.answerSelected(
            context: context,
            questionID: "stair_stepper_experience",
            answerID: "regular_stepper",
            answerIndex: 2
        ).record

        #expect(record.name == "onboarding_answer_selected")
        #expect(record.parameters["question_id"] == .string("stair_stepper_experience"))
        #expect(record.parameters["answer_id"] == .string("regular_stepper"))
        #expect(record.parameters["answer_index"] == .int(2))
    }

    @Test
    func authStartedUsesStableAuthContext() {
        let record = OnboardingAnalyticsEvent.authStarted(provider: "apple").record

        #expect(record.name == "onboarding_auth_started")
        #expect(record.parameters["flow_id"] == .string("pre_auth_auth"))
        #expect(record.parameters["step_id"] == .string("auth"))
        #expect(record.parameters["provider"] == .string("apple"))
    }

    @Test
    func notificationPermissionSelectedUsesStatusWithoutRawPermissionPayload() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "notifications",
            stepIndex: 5,
            stepCount: 8
        )

        let record = OnboardingAnalyticsEvent.notificationPermissionSelected(
            context: context,
            status: "skipped"
        ).record

        #expect(record.name == "onboarding_notification_permission_selected")
        #expect(record.parameters["step_id"] == .string("notifications"))
        #expect(record.parameters["status"] == .string("skipped"))
    }

    @Test
    func firstClimbSelectedIncludesRecommendationContext() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "first_climb",
            stepIndex: 7,
            stepCount: 8
        )

        let record = OnboardingAnalyticsEvent.firstClimbSelected(
            context: context,
            climbID: "empire-state-building",
            climbName: "Empire State Building"
        ).record

        #expect(record.name == "onboarding_first_climb_selected")
        #expect(record.parameters["flow_id"] == .string("post_auth_onboarding"))
        #expect(record.parameters["climb_id"] == .string("empire-state-building"))
        #expect(record.parameters["climb_name"] == .string("Empire State Building"))
    }

    @Test
    func onboardingPaywallReachedKeepsPlacementAndSource() {
        let record = OnboardingAnalyticsEvent.paywallReached(
            placement: "onboarding_paywall",
            source: "post_auth_onboarding"
        ).record

        #expect(record.name == "onboarding_paywall_reached")
        #expect(record.parameters["flow_id"] == .string("post_auth_onboarding"))
        #expect(record.parameters["step_id"] == .string("paywall"))
        #expect(record.parameters["placement"] == .string("onboarding_paywall"))
        #expect(record.parameters["source"] == .string("post_auth_onboarding"))
    }
}
