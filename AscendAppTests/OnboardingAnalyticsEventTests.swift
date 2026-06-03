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
}
