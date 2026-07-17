import Testing
@testable import AscendApp

struct OnboardingAnalyticsEventTests {
    @Test
    func profileScreenCompletedUsesStableEventNameWithoutAnswerProperties() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "gender",
            stepIndex: 6,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: context,
            inputType: "single_select",
            properties: [:]
        ).record

        #expect(record.name == "onboarding_screen_completed")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
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
    func profileTextScreenCompletedDoesNotRecordRawTextAnswer() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "displayName",
            stepIndex: 0,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: context,
            inputType: "text",
            properties: [:]
        ).record

        #expect(record.name == "onboarding_screen_completed")
        expectStringParameter(record, "input_type", "text")
        expectBoolParameter(record, "completed", true)
        expectMissingParameter(record, "question_id")
        expectMissingParameter(record, "answer_id")
        expectMissingParameter(record, "has_answer")
        expectMissingParameter(record, "selection_type")
        expectMissingParameter(record, "answer_index")
    }

    @Test
    func surveyQuestionAnsweredUsesStableEventNameAndAnswerProperties() {
        let context = OnboardingAnalyticsContext(
            flowID: "post_auth_onboarding",
            stepID: "stair_stepper_baseline",
            stepIndex: 1,
            stepCount: 13
        )

        let record = OnboardingAnalyticsEvent.questionAnswered(
            context: context,
            questionID: "stair_stepper_baseline",
            inputType: "single_select",
            selectionType: "single_select",
            answerID: "never_tried",
            answerIndex: 0,
            properties: ["answer_count": .int(1)]
        ).record

        #expect(record.name == "onboarding_question_answered")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "stair_stepper_baseline")
        expectStringParameter(record, "screen_id", "stair_stepper_baseline")
        expectStringParameter(record, "question_id", "stair_stepper_baseline")
        expectStringParameter(record, "input_type", "single_select")
        expectStringParameter(record, "selection_type", "single_select")
        expectStringParameter(record, "answer_id", "never_tried")
        expectIntParameter(record, "answer_index", 0)
        expectIntParameter(record, "answer_count", 1)
        expectBoolParameter(record, "has_answer", true)
    }

    @Test
    func authStartedUsesStableAuthContext() {
        let record = OnboardingAnalyticsEvent.authStarted(provider: "apple").record

        #expect(record.name == "onboarding_auth_started")
        expectStringParameter(record, "flow_id", "pre_auth_auth")
        expectStringParameter(record, "step_id", "auth")
        expectStringParameter(record, "provider", "apple")
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

        #expect(record.name == "onboarding_question_answered")
        expectStringParameter(record, "step_id", "notifications")
        expectStringParameter(record, "question_id", "notifications")
        expectStringParameter(record, "input_type", "permission_prompt")
        expectStringParameter(record, "selection_type", "single_select")
        expectStringParameter(record, "answer_id", "skip")
        expectStringParameter(record, "status", "skip")
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

        #expect(record.name == "onboarding_question_answered")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
        expectStringParameter(record, "question_id", "first_climb")
        expectStringParameter(record, "input_type", "single_select")
        expectStringParameter(record, "selection_type", "single_select")
        expectStringParameter(record, "answer_id", "empire-state-building")
        expectStringParameter(record, "climb_id", "empire-state-building")
        expectStringParameter(record, "climb_name", "Empire State Building")
    }

    @Test
    func onboardingPaywallReachedKeepsPlacementAndSource() {
        let record = OnboardingAnalyticsEvent.paywallReached(
            placement: "onboarding_paywall",
            source: "post_auth_onboarding"
        ).record

        #expect(record.name == "onboarding_paywall_reached")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "paywall")
        expectStringParameter(record, "placement", "onboarding_paywall")
        expectStringParameter(record, "source", "post_auth_onboarding")
    }

    @Test
    func welcomeScreenViewedUsesUniqueWelcomeStep() {
        let record = OnboardingAnalyticsEvent.screenViewed(
            context: OnboardingAnalyticsEvent.welcomeContext
        ).record

        #expect(record.name == "onboarding_screen_viewed")
        expectStringParameter(record, "flow_id", "pre_auth_welcome")
        expectStringParameter(record, "step_id", "welcome")
        expectStringParameter(record, "screen_id", "welcome")
        expectBoolParameter(record, "viewed", true)
    }

    @Test
    func welcomeScreenCompletedRecordsGetStartedTap() {
        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: OnboardingAnalyticsEvent.welcomeContext,
            inputType: "button",
            properties: [:]
        ).record

        #expect(record.name == "onboarding_screen_completed")
        expectStringParameter(record, "step_id", "welcome")
        expectStringParameter(record, "input_type", "button")
        expectBoolParameter(record, "completed", true)
    }

    @Test
    func authScreenViewedUsesStableAuthContext() {
        let record = OnboardingAnalyticsEvent.screenViewed(
            context: OnboardingAnalyticsEvent.authContext
        ).record

        #expect(record.name == "onboarding_screen_viewed")
        expectStringParameter(record, "flow_id", "pre_auth_auth")
        expectStringParameter(record, "step_id", "auth")
        expectStringParameter(record, "screen_id", "auth")
    }

    @Test
    func paywallScreenViewedJoinsPostAuthOnboardingFunnel() {
        let record = OnboardingAnalyticsEvent.screenViewed(
            context: OnboardingAnalyticsEvent.paywallContext
        ).record

        #expect(record.name == "onboarding_screen_viewed")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "paywall")
        expectStringParameter(record, "screen_id", "paywall")
        expectIntParameter(record, "step_index", PostAuthOnboardingStage.plannedStepCount)
    }

    @Test
    func paywallFollowsTheLastPostAuthStage() {
        #expect(
            OnboardingAnalyticsEvent.paywallContext.stepIndex > PostAuthOnboardingStage.firstClimb.progressIndex
        )
    }

    @Test
    func flowStartedUsesStableEventName() {
        let record = OnboardingAnalyticsEvent.flowStarted(
            context: PostAuthOnboardingStage.displayName.analyticsContext
        ).record

        #expect(record.name == "onboarding_flow_started")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "displayName")
        expectIntParameter(record, "step_index", 0)
    }

    @Test
    func backTappedNamesTheStepBeingLeft() {
        let record = OnboardingAnalyticsEvent.backTapped(
            context: PostAuthOnboardingStage.gender.analyticsContext
        ).record

        #expect(record.name == "onboarding_back_tapped")
        expectStringParameter(record, "flow_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "gender")
        expectStringParameter(record, "from_step", "gender")
    }

    @Test
    func preAuthBackTapNamesTheValuePageBeingLeft() throws {
        let pages = OnboardingValuePages.all
        let context = try #require(
            OnboardingValueCarouselView.analyticsContext(pages: pages, index: 1)
        )

        let record = OnboardingAnalyticsEvent.backTapped(context: context).record

        #expect(record.name == "onboarding_back_tapped")
        expectStringParameter(record, "flow_id", "pre_auth_value_onboarding")
        expectStringParameter(record, "from_step", pages[1].id)
    }
}

struct OnboardingValueCarouselAnalyticsContextTests {
    @Test
    func contextUsesPageIdentityAndPosition() throws {
        let pages = OnboardingValuePages.all
        let context = try #require(OnboardingValueCarouselView.analyticsContext(pages: pages, index: 0))

        #expect(context.flowID == "pre_auth_value_onboarding")
        #expect(context.stepID == pages[0].id)
        #expect(context.stepIndex == 0)
        #expect(context.stepCount == pages.count)
    }

    @Test
    func everyValuePageHasAUniqueStepID() {
        let pages = OnboardingValuePages.all
        let stepIDs = pages.indices.compactMap {
            OnboardingValueCarouselView.analyticsContext(pages: pages, index: $0)?.stepID
        }

        #expect(stepIDs.count == pages.count)
        #expect(Set(stepIDs).count == pages.count)
    }

    @Test
    func outOfRangeIndexHasNoContext() {
        let pages = OnboardingValuePages.all

        #expect(OnboardingValueCarouselView.analyticsContext(pages: pages, index: pages.count) == nil)
        #expect(OnboardingValueCarouselView.analyticsContext(pages: pages, index: -1) == nil)
        #expect(OnboardingValueCarouselView.analyticsContext(pages: [], index: 0) == nil)
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
