import Testing
@testable import AscendApp

struct OnboardingAnalyticsEventTests {
    @Test
    func profileScreenCompletedUsesFigmaEventNameWithoutAnswerProperties() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "gender",
            stepIndex: 6,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: context,
            eventName: "division_inputted",
            inputType: "single_select",
            properties: [:]
        ).record

        #expect(record.name == "division_inputted")
        #expect(record.parameters["flow_id"] == .string("post_auth_onboarding"))
        #expect(record.parameters["flow_version"] == .string("v1"))
        #expect(record.parameters["step_id"] == .string("gender"))
        #expect(record.parameters["screen_id"] == .string("gender"))
        #expect(record.parameters["input_type"] == .string("single_select"))
        #expect(record.parameters["completed"] == .bool(true))
        #expect(record.parameters["question_id"] == nil)
        #expect(record.parameters["selection_type"] == nil)
        #expect(record.parameters["answer_id"] == nil)
        #expect(record.parameters["answer_index"] == nil)
        #expect(record.parameters["has_answer"] == nil)
    }

    @Test
    func profileTextScreenCompletedDoesNotRecordRawTextAnswer() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "displayName",
            stepIndex: 0,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: context,
            eventName: "name_inputted",
            inputType: "text",
            properties: [:]
        ).record

        #expect(record.name == "name_inputted")
        #expect(record.parameters["input_type"] == .string("text"))
        #expect(record.parameters["completed"] == .bool(true))
        #expect(record.parameters["question_id"] == nil)
        #expect(record.parameters["answer_id"] == nil)
        #expect(record.parameters["has_answer"] == nil)
        #expect(record.parameters["selection_type"] == nil)
        #expect(record.parameters["answer_index"] == nil)
    }

    @Test
    func surveyQuestionAnsweredUsesQuestionEventNameAndAnswerProperties() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "stair_stepper_baseline",
            stepIndex: 1,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.questionAnswered(
            context: context,
            eventName: "stair_stepper_baseline_answered",
            questionID: "stair_stepper_baseline",
            inputType: "single_select",
            selectionType: "single_select",
            answerID: "never_tried",
            answerIndex: 0,
            properties: ["answer_count": .int(1)]
        ).record

        #expect(record.name == "stair_stepper_baseline_answered")
        #expect(record.parameters["flow_id"] == .string("post_auth_onboarding"))
        #expect(record.parameters["step_id"] == .string("stair_stepper_baseline"))
        #expect(record.parameters["screen_id"] == .string("stair_stepper_baseline"))
        #expect(record.parameters["question_id"] == .string("stair_stepper_baseline"))
        #expect(record.parameters["input_type"] == .string("single_select"))
        #expect(record.parameters["selection_type"] == .string("single_select"))
        #expect(record.parameters["answer_id"] == .string("never_tried"))
        #expect(record.parameters["answer_index"] == .int(0))
        #expect(record.parameters["answer_count"] == .int(1))
        #expect(record.parameters["has_answer"] == .bool(true))
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
    func notificationPermissionSelectedUsesStatusAsSingleSelectAnswer() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "notifications",
            stepIndex: 10,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.notificationPermissionSelected(
            context: context,
            status: "skip"
        ).record

        #expect(record.name == "notifications_inputted")
        #expect(record.parameters["step_id"] == .string("notifications"))
        #expect(record.parameters["question_id"] == .string("notifications"))
        #expect(record.parameters["input_type"] == .string("permission_prompt"))
        #expect(record.parameters["selection_type"] == .string("single_select"))
        #expect(record.parameters["answer_id"] == .string("skip"))
        #expect(record.parameters["status"] == .string("skip"))
    }

    @Test
    func firstClimbSelectedIncludesRecommendationContext() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "first_climb",
            stepIndex: 12,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.firstClimbSelected(
            context: context,
            climbID: "empire-state-building",
            climbName: "Empire State Building"
        ).record

        #expect(record.name == "first_climb_selected")
        #expect(record.parameters["flow_id"] == .string("post_auth_onboarding"))
        #expect(record.parameters["question_id"] == .string("first_climb"))
        #expect(record.parameters["input_type"] == .string("single_select"))
        #expect(record.parameters["selection_type"] == .string("single_select"))
        #expect(record.parameters["answer_id"] == .string("empire-state-building"))
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
