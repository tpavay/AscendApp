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
    func profileTextScreenCompletedDoesNotRecordRawTextAnswer() {
        let context = OnboardingAnalyticsContext(
            segmentID: "post_auth_onboarding",
            stepID: "displayName"
        )

        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: context,
            inputType: "text",
            properties: ["display_name_provided": .bool(true)]
        ).record

        #expect(record.name == "onboarding_screen_completed")
        expectStringParameter(record, "input_type", "text")
        expectBoolParameter(record, "completed", true)
        expectBoolParameter(record, "display_name_provided", true)
        expectMissingParameter(record, "question_id")
        expectMissingParameter(record, "answer_id")
        expectMissingParameter(record, "has_answer")
        expectMissingParameter(record, "selection_type")
        expectMissingParameter(record, "answer_index")
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
            answerID: "never_tried",
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
        expectStringParameter(record, "answer_id", "never_tried")
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
    func firstClimbSelectedIncludesRecommendationContext() {
        let context = OnboardingAnalyticsContext(
            segmentID: "post_auth_onboarding",
            stepID: "first_climb"
        )

        let record = OnboardingAnalyticsEvent.firstClimbSelected(
            context: context,
            climbID: "empire-state-building",
            climbName: "Empire State Building"
        ).record

        #expect(record.name == "onboarding_question_answered")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
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
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
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
    func bodyMetricsCompletionCapturesHeightWeightAndMeasurementSystem() {
        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: PostAuthOnboardingStage.weight.analyticsContext,
            inputType: PostAuthOnboardingStage.weight.analyticsInputType,
            properties: [
                "measurement_system": .string("imperial"),
                "profile_height_group": .string(
                    OnboardingAnalyticsUserProperties.heightGroupValue(forHeightCm: 177.8)
                ),
                "profile_weight_group": .string(
                    OnboardingAnalyticsUserProperties.weightGroupValue(forWeightKg: 83.9)
                )
            ]
        ).record

        expectStringParameter(record, "screen_id", "weight")
        expectStringParameter(record, "input_type", "measurement")
        expectStringParameter(record, "measurement_system", "imperial")
        expectStringParameter(record, "profile_height_group", "165_179_cm")
        expectStringParameter(record, "profile_weight_group", "150_199_lb")
    }

    @Test
    func locationCompletionCapturesCountryAndSelectionMethod() {
        let record = OnboardingAnalyticsEvent.screenCompleted(
            context: PostAuthOnboardingStage.location.analyticsContext,
            inputType: PostAuthOnboardingStage.location.analyticsInputType,
            properties: [
                "profile_country": .string("US"),
                "selection_method": .string("current_location")
            ]
        ).record

        expectStringParameter(record, "screen_id", "location")
        expectStringParameter(record, "input_type", "location")
        expectStringParameter(record, "profile_country", "US")
        expectStringParameter(record, "selection_method", "current_location")
    }

    @Test
    func demographicCompletionsCaptureSelectedBuckets() {
        let genderRecord = OnboardingAnalyticsEvent.screenCompleted(
            context: PostAuthOnboardingStage.gender.analyticsContext,
            inputType: PostAuthOnboardingStage.gender.analyticsInputType,
            properties: ["profile_gender": .string("non_binary")]
        ).record
        let ageRecord = OnboardingAnalyticsEvent.screenCompleted(
            context: PostAuthOnboardingStage.age.analyticsContext,
            inputType: PostAuthOnboardingStage.age.analyticsInputType,
            properties: ["profile_age_group": .string("25_34")]
        ).record

        expectStringParameter(genderRecord, "profile_gender", "non_binary")
        expectStringParameter(ageRecord, "profile_age_group", "25_34")
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
    func paywallScreenViewedJoinsPostAuthOnboardingFunnel() {
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
    func paywallFollowsTheLastPostAuthStage() {
        #expect(
            OnboardingAnalyticsEvent.paywallContext.stepIndex > PostAuthOnboardingStage.firstClimb.progressIndex
        )
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
            context: PostAuthOnboardingStage.gender.analyticsContext,
            inputType: "button"
        ).record

        #expect(record.name == "onboarding_back_tapped")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "post_auth_onboarding")
        expectStringParameter(record, "step_id", "gender")
        expectStringParameter(record, "from_step", "gender")
        expectStringParameter(record, "input_type", "button")
    }

    @Test
    func preAuthBackTapNamesTheValuePageBeingLeft() throws {
        let pages = OnboardingValuePages.all
        let context = try #require(
            OnboardingValueCarouselView.analyticsContext(pages: pages, index: 1)
        )

        let record = OnboardingAnalyticsEvent.backTapped(context: context, inputType: "gesture").record

        #expect(record.name == "onboarding_back_tapped")
        expectStringParameter(record, "flow_id", "onboarding")
        expectStringParameter(record, "segment_id", "pre_auth_value_onboarding")
        expectStringParameter(record, "from_step", pages[1].id)
        expectStringParameter(record, "input_type", "gesture")
    }
}

@MainActor
struct OnboardingScreenViewCoverageTests {
    @Test
    func everyVisibleOnboardingScreenEmitsExactlyOnce() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        var recorder = OnboardingScreenViewRecorder()
        let contexts = canonicalVisibleContexts()

        for context in contexts {
            recorder.recordIfNeeded(context, telemetry: telemetry)
            recorder.recordIfNeeded(context, telemetry: telemetry)
        }

        let records = sink.records.filter { $0.name == "onboarding_screen_viewed" }
        let screenIDs = records.compactMap { record -> String? in
            guard case .string(let screenID)? = record.parameters["screen_id"] else { return nil }
            return screenID
        }

        #expect(screenIDs == [
            "welcome",
            "watch_yourself_get_better",
            "reason_to_come_back",
            "auth",
            "displayName",
            "stair_stepper_baseline",
            "exercise_level",
            "goal",
            "motivation",
            "plan",
            "summit_landmarks",
            "real_time",
            "daily_climbs",
            "gender",
            "age",
            "weight",
            "location",
            "notifications",
            "loading",
            "first_climb",
            "paywall"
        ])
        #expect(Set(screenIDs).count == 21)
        #expect(screenIDs.contains("features") == false)
        #expect(records.allSatisfy { $0.parameters["viewed"] == .bool(true) })
        #expect(records.allSatisfy { $0.parameters["step_id"] == $0.parameters["screen_id"] })
        #expect(records.allSatisfy { $0.parameters["flow_id"] == .string("onboarding") })
        #expect(records.allSatisfy { $0.parameters["flow_version"] == .string("v1") })
        #expect(records.allSatisfy { $0.parameters["segment_id"] != nil })
        #expect(records.map { $0.parameters["step_index"] } == (0..<21).map(TelemetryValue.int))
        #expect(records.allSatisfy { $0.parameters["step_count"] == .int(21) })
        #expect(records.allSatisfy { $0.parameters["app_environment"] != nil })
    }

    @Test
    func featuresContainerHasNoVisibleScreenContext() {
        #expect(PostAuthOnboardingStage.features.visibleScreenAnalyticsContext == nil)
        #expect(
            PostAuthOnboardingStage.allCases
                .filter { $0 != .features }
                .allSatisfy { $0.visibleScreenAnalyticsContext != nil }
        )
    }

    private func canonicalVisibleContexts() -> [OnboardingAnalyticsContext] {
        var contexts = [OnboardingAnalyticsEvent.welcomeContext]
        contexts.append(contentsOf: OnboardingValuePages.all.indices.compactMap {
            OnboardingValueCarouselView.analyticsContext(
                pages: OnboardingValuePages.all,
                index: $0
            )
        })
        contexts.append(OnboardingAnalyticsEvent.authContext)

        for stage in PostAuthOnboardingStage.allCases {
            if stage == .features {
                contexts.append(contentsOf: OnboardingFeatureGuideFlowScreen.analyticsContexts(
                    segmentID: "post_auth_features"
                ))
            } else if let context = stage.visibleScreenAnalyticsContext {
                contexts.append(context)
            }
        }

        contexts.append(OnboardingAnalyticsEvent.paywallContext)
        return contexts
    }
}

@MainActor
struct OnboardingValueCarouselAnalyticsContextTests {
    @Test
    func contextUsesPageIdentityAndPosition() throws {
        let pages = OnboardingValuePages.all
        let context = try #require(OnboardingValueCarouselView.analyticsContext(pages: pages, index: 0))

        #expect(context.segmentID == "pre_auth_value_onboarding")
        #expect(context.stepID == pages[0].id)
        #expect(context.stepIndex == 1)
        #expect(context.stepCount == 21)
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
