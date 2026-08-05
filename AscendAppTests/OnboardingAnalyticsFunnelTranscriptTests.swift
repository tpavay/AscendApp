import Foundation
import Testing
@testable import AscendApp

/// The funnel is only readable end to end as a transcript: one row per visible screen, the
/// events that screen ships, and the sub-properties those events carry. This renders that
/// transcript from real emissions and fails the moment a visible screen stops reporting its
/// view, or an interactive screen stops reporting the decision the user made on it.
@MainActor
struct OnboardingAnalyticsFunnelTranscriptTests {
    @Test
    func everyVisibleScreenShipsAViewAndEveryInteractiveScreenShipsItsDecision() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let defaults = makeOnboardingDefaults()
        let lifecycle = OnboardingFlowAnalyticsCoordinator(
            userDefaults: defaults,
            telemetry: telemetry
        )
        var recorder = OnboardingScreenViewRecorder()
        let steps = Self.funnelSteps

        lifecycle.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)

        for step in steps {
            recorder.recordIfNeeded(step.context, telemetry: telemetry)
            // A re-render of the same screen must never bank a second view.
            recorder.recordIfNeeded(step.context, telemetry: telemetry)
            step.interactions.forEach { telemetry.track($0) }
        }

        // The routed app-access gate joins the same funnel, and owns the paywall screen view.
        let monetization = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: telemetry,
            onboardingLifecycle: lifecycle
        )
        monetization.presentPaywall(.appAccessGate, params: ["source": "onboarding"])
        Self.paywallOutcomes.forEach { telemetry.track($0) }
        lifecycle.recordFlowCompletedIfNeeded(reason: .purchase)

        let records = sink.records
        let transcript = Self.transcript(
            records: records,
            orderedScreenIDs: steps.map(\.screenID) + ["paywall"]
        )
        print(transcript)
        print(Self.contractSummary(records: records))

        let viewedScreenIDs = records
            .filter { $0.name == "onboarding_screen_viewed" }
            .compactMap { record -> String? in
                guard case .string(let screenID)? = record.parameters["screen_id"] else { return nil }
                return screenID
            }

        #expect(viewedScreenIDs == steps.map(\.screenID) + ["paywall"])
        #expect(viewedScreenIDs.count == 21)
        #expect(Set(viewedScreenIDs).count == 21)
        #expect(viewedScreenIDs.contains("features") == false)
        #expect(records.filter { $0.name == "onboarding_flow_started" }.count == 1)
        #expect(records.filter { $0.name == "onboarding_flow_completed" }.count == 1)
        #expect(records.filter { $0.name == "onboarding_screen_completed" }.count == 19)
        #expect(records.filter { $0.name == "onboarding_question_answered" }.count == 7)
        #expect(records.filter { $0.name == "onboarding_auth_started" }.count == 1)
        #expect(records.filter { $0.name == "onboarding_auth_completed" }.count == 1)
        #expect(records.filter { $0.name == "onboarding_auth_failed" }.isEmpty)
        #expect(records.filter { $0.name == "onboarding_paywall_reached" }.count == 1)

        let onboardingRecords = records.filter { $0.name.hasPrefix("onboarding_") }
        #expect(onboardingRecords.allSatisfy { $0.parameters["flow_id"] == .string("onboarding") })
        #expect(onboardingRecords.allSatisfy { $0.parameters["flow_version"] == .string("v1") })
        #expect(onboardingRecords.allSatisfy { $0.parameters["step_count"] == .int(21) })

        let completion = records.first { $0.name == "onboarding_flow_completed" }
        #expect(completion?.parameters["step_id"] == .string("paywall"))
        #expect(completion?.parameters["step_index"] == .int(20))
        #expect(completion?.parameters["completion_reason"] == .string("purchase"))

        for step in steps where step.isInteractive {
            let decisions = records.filter { record in
                record.name != "onboarding_screen_viewed"
                    && record.parameters["step_id"] == .string(step.screenID)
                    && !Self.subProperties(of: record).isEmpty
            }

            #expect(decisions.isEmpty == false, "\(step.screenID) reports no decision with sub-properties")
        }
    }

    /// The interrupted pass reads as a transcript too: a relaunch mid-flow continues the same
    /// pass, so the funnel sees one start, and the screen the climber comes back to is the only
    /// one that says it is a resume.
    @Test
    func aRelaunchMidPassContinuesTheSamePassAndMarksOnlyTheReshownScreen() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let defaults = makeOnboardingDefaults()

        let firstLaunch = OnboardingFlowAnalyticsCoordinator(
            userDefaults: defaults,
            telemetry: telemetry
        )
        var firstLaunchRecorder = OnboardingScreenViewRecorder()
        let beforeQuitting = Array(Self.funnelSteps.prefix(3))

        for step in beforeQuitting {
            firstLaunch.recordFlowStartedIfNeeded(context: step.context)
            firstLaunchRecorder.recordIfNeeded(
                step.context,
                resume: firstLaunch.consumeScreenResumeFlag(),
                telemetry: telemetry
            )
        }

        // The process dies here. A relaunch rebuilds the coordinator over the persisted pass and
        // starts a fresh in-memory view set, exactly as the running app does.
        let relaunch = OnboardingFlowAnalyticsCoordinator(
            userDefaults: defaults,
            telemetry: telemetry
        )
        var relaunchRecorder = OnboardingScreenViewRecorder()

        for step in Self.funnelSteps[2...4] {
            relaunch.recordFlowStartedIfNeeded(context: step.context)
            relaunchRecorder.recordIfNeeded(
                step.context,
                resume: relaunch.consumeScreenResumeFlag(),
                telemetry: telemetry
            )
        }

        let records = sink.records
        print(
            Self.transcript(
                records: records,
                orderedScreenIDs: Self.funnelSteps.prefix(5).map(\.screenID),
                title: "RESUMED PASS TRANSCRIPT - relaunch mid-flow, one pass"
            )
        )

        #expect(records.filter { $0.name == "onboarding_flow_started" }.count == 1)
        #expect(records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)

        let resumedScreenIDs = records
            .filter { $0.name == "onboarding_screen_viewed" && $0.parameters["resume"] == .bool(true) }
            .compactMap { record -> String? in
                guard case .string(let screenID)? = record.parameters["screen_id"] else { return nil }
                return screenID
            }

        #expect(resumedScreenIDs == ["reason_to_come_back"])
    }

    /// Back navigation is a user action, not a lifecycle: each deliberate back reports itself once,
    /// names the step being left, and leaves the pass it is inside untouched.
    @Test
    func eachDeliberateBackReportsItselfOnceWithoutOpeningAnotherLifecycle() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let defaults = makeOnboardingDefaults()
        let lifecycle = OnboardingFlowAnalyticsCoordinator(
            userDefaults: defaults,
            telemetry: telemetry
        )
        var recorder = OnboardingScreenViewRecorder()
        let walkedForward = Array(Self.funnelSteps.prefix(3))

        for step in walkedForward {
            lifecycle.recordFlowStartedIfNeeded(context: step.context)
            recorder.recordIfNeeded(
                step.context,
                resume: lifecycle.consumeScreenResumeFlag(),
                telemetry: telemetry
            )
        }

        // Two deliberate back actions: the carousel's backward swipe, then the chrome back button.
        telemetry.track(
            OnboardingAnalyticsEvent.backTapped(
                context: walkedForward[2].context,
                inputType: "gesture"
            )
        )
        telemetry.track(
            OnboardingAnalyticsEvent.backTapped(
                context: walkedForward[1].context,
                inputType: "button"
            )
        )

        // Walking forward again re-enters the same pass rather than opening a second one.
        for step in walkedForward {
            lifecycle.recordFlowStartedIfNeeded(context: step.context)
        }

        let records = sink.records
        print(
            Self.transcript(
                records: records,
                orderedScreenIDs: walkedForward.map(\.screenID),
                title: "BACK-NAVIGATION TRANSCRIPT - two deliberate back actions, one pass"
            )
        )

        let backEvents = records.filter { $0.name == "onboarding_back_tapped" }
        #expect(backEvents.count == 2)
        #expect(backEvents.first?.parameters["from_step"] == .string("reason_to_come_back"))
        #expect(backEvents.first?.parameters["input_type"] == .string("gesture"))
        #expect(backEvents.last?.parameters["from_step"] == .string("watch_yourself_get_better"))
        #expect(backEvents.last?.parameters["input_type"] == .string("button"))
        #expect(records.filter { $0.name == "onboarding_flow_started" }.count == 1)
        #expect(records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)
    }
}

// MARK: - Funnel definition

private extension OnboardingAnalyticsFunnelTranscriptTests {
    struct Step {
        let context: OnboardingAnalyticsContext
        let interactions: [OnboardingAnalyticsEvent]
        let isInteractive: Bool

        var screenID: String { context.stepID }

        init(
            _ context: OnboardingAnalyticsContext,
            interactions: [OnboardingAnalyticsEvent],
            isInteractive: Bool = true
        ) {
            self.context = context
            self.interactions = interactions
            self.isInteractive = isInteractive
        }
    }

    static var funnelSteps: [Step] {
        var steps: [Step] = [
            Step(
                OnboardingAnalyticsEvent.welcomeContext,
                interactions: [
                    .screenCompleted(
                        context: OnboardingAnalyticsEvent.welcomeContext,
                        inputType: "button",
                        properties: ["action_id": .string("get_started")]
                    )
                ]
            )
        ]

        steps.append(contentsOf: valueCarouselSteps())
        steps.append(
            Step(
                OnboardingAnalyticsEvent.authContext,
                interactions: [
                    .authStarted(provider: "apple"),
                    .authCompleted(provider: "apple")
                ]
            )
        )
        steps.append(contentsOf: postAuthSteps())
        return steps
    }

    static func valueCarouselSteps() -> [Step] {
        let pages = OnboardingValuePages.all
        return pages.indices.compactMap { index in
            guard let context = OnboardingValueCarouselView.analyticsContext(
                pages: pages,
                index: index
            ) else { return nil }

            return Step(
                context,
                interactions: [
                    .screenCompleted(
                        context: context,
                        inputType: index == 0 ? "gesture" : "button",
                        properties: [
                            "action_id": .string(index == 0 ? "swipe_forward" : "continue")
                        ]
                    )
                ]
            )
        }
    }

    static func postAuthSteps() -> [Step] {
        PostAuthOnboardingStage.allCases.flatMap { stage -> [Step] in
            guard let context = stage.visibleScreenAnalyticsContext else {
                // The features stage is a container, not a screen: its three guide screens are.
                return featureGuideSteps()
            }

            return [
                Step(
                    context,
                    interactions: interactions(for: stage, context: context),
                    isInteractive: stage != .planLoading
                )
            ]
        }
    }

    static func featureGuideSteps() -> [Step] {
        OnboardingFeatureGuideFlowScreen
            .analyticsContexts(segmentID: "post_auth_features")
            .map { context in
                Step(
                    context,
                    interactions: [
                        .screenCompleted(
                            context: context,
                            inputType: "button",
                            properties: ["action_id": .string("continue")]
                        )
                    ]
                )
            }
    }

    /// Mirrors the arguments each post-auth screen passes at its own call site, so the
    /// transcript shows the payload the shipped screen sends rather than a stand-in.
    static func interactions(
        for stage: PostAuthOnboardingStage,
        context: OnboardingAnalyticsContext
    ) -> [OnboardingAnalyticsEvent] {
        let completed = { (properties: [String: TelemetryValue]) in
            OnboardingAnalyticsEvent.screenCompleted(
                context: context,
                inputType: stage.analyticsInputType,
                properties: properties
            )
        }

        switch stage {
        case .displayName:
            return [completed(["display_name_provided": .bool(true)])]
        case .stairStepperBaseline, .exerciseLevel, .goal, .motivation, .plan:
            return surveyInteractions(for: stage, context: context) + [
                completed(["answer_count": .int(1)])
            ]
        case .gender:
            return [completed(["profile_gender": .string("woman")])]
        case .age:
            return [
                completed([
                    "profile_age_group": .string(
                        OnboardingAnalyticsUserProperties.ageGroupValue(for: 32)
                    )
                ])
            ]
        case .weight:
            return [
                completed([
                    "measurement_system": .string("imperial"),
                    "profile_height_group": .string(
                        OnboardingAnalyticsUserProperties.heightGroupValue(forHeightCm: 177.8)
                    ),
                    "profile_weight_group": .string(
                        OnboardingAnalyticsUserProperties.weightGroupValue(forWeightKg: 83.9)
                    )
                ])
            ]
        case .location:
            return [
                completed([
                    "profile_country": .string("US"),
                    "selection_method": .string("current_location")
                ])
            ]
        case .notifications:
            return [
                .notificationPermissionSelected(context: context, status: "allow"),
                completed(["status": .string("allow")])
            ]
        case .planLoading:
            return [completed([:])]
        case .firstClimb:
            return [
                .firstClimbSelected(
                    context: context,
                    climbID: "eiffel-tower",
                    climbName: "Eiffel Tower"
                ),
                completed([
                    "climb_id": .string("eiffel-tower"),
                    "climb_name": .string("Eiffel Tower")
                ])
            ]
        case .features:
            return []
        }
    }

    static func surveyInteractions(
        for stage: PostAuthOnboardingStage,
        context: OnboardingAnalyticsContext
    ) -> [OnboardingAnalyticsEvent] {
        guard let question = PreAuthSurveyQuestion.question(for: stage.rawValue),
              let option = question.options.first else { return [] }

        return [
            .questionAnswered(
                context: context,
                questionID: question.id,
                inputType: question.selectionMode.analyticsInputType,
                selectionType: question.selectionMode.analyticsInputType,
                answerID: option.id,
                answerIndex: 0,
                properties: ["answer_count": .int(1)]
            )
        ]
    }

    static var paywallOutcomes: [PaywallAnalyticsEvent] {
        [
            .purchaseControllerCompleted(productID: "ascend_yearly", outcome: "purchased")
        ]
    }
}

// MARK: - Transcript rendering

private extension OnboardingAnalyticsFunnelTranscriptTests {
    static let contextParameterKeys: Set<String> = [
        "flow_id", "flow_version", "segment_id", "step_id", "step_index", "step_count",
        "screen_id", "app_environment", "build_config", "app_version", "build_number"
    ]

    static func subProperties(of record: EnvelopedTelemetryRecord) -> [String: TelemetryValue] {
        record.parameters.filter { !contextParameterKeys.contains($0.key) }
    }

    static func transcript(
        records: [EnvelopedTelemetryRecord],
        orderedScreenIDs: [String],
        title: String = "ONBOARDING FUNNEL TRANSCRIPT - events as delivered to MixpanelTelemetrySink"
    ) -> String {
        var lines = [
            "",
            title,
            "",
            "| # | Screen | Segment | Event | Sub-properties |",
            "| --- | --- | --- | --- | --- |"
        ]

        for (index, screenID) in orderedScreenIDs.enumerated() {
            let screenRecords = records.filter { $0.parameters["step_id"] == .string(screenID) }

            for (recordIndex, record) in screenRecords.enumerated() {
                let subProperties = subProperties(of: record)
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(describe($0.value))" }
                    .joined(separator: ", ")
                var segmentID = ""
                if case .string(let value)? = record.parameters["segment_id"] {
                    segmentID = value
                }

                lines.append(
                    "| \(recordIndex == 0 ? String(index + 1) : "") "
                        + "| \(recordIndex == 0 ? screenID : "") "
                        + "| \(recordIndex == 0 ? segmentID : "") "
                        + "| \(record.name) "
                        + "| \(subProperties.isEmpty ? "-" : subProperties) |"
                )
            }
        }

        let unscoped = records.filter { $0.parameters["step_id"] == nil }
        if !unscoped.isEmpty {
            lines.append("")
            lines.append("| Paywall outcome event | Sub-properties |")
            lines.append("| --- | --- |")
            for record in unscoped {
                let subProperties = subProperties(of: record)
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(describe($0.value))" }
                    .joined(separator: ", ")
                lines.append("| \(record.name) | \(subProperties) |")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// The transcript shows the payload per screen; this shows the two things the funnel contract
    /// is counted on - how many of each event one clean pass emitted, and the canonical context
    /// every one of them carried.
    static func contractSummary(records: [EnvelopedTelemetryRecord]) -> String {
        let onboardingRecords = records.filter { $0.name.hasPrefix("onboarding_") }
        var lines = [
            "",
            "CLEAN-PASS EVENT COUNTS",
            "",
            "| Event | Count |",
            "| --- | --- |"
        ]

        let counts = onboardingRecords.reduce(into: [String: Int]()) { $0[$1.name, default: 0] += 1 }
        for name in counts.keys.sorted() {
            lines.append("| \(name) | \(counts[name] ?? 0) |")
        }

        lines.append(contentsOf: [
            "",
            "CANONICAL ONBOARDING CONTEXT - every onboarding event, in emission order",
            "",
            "| Event | flow_id | flow_version | step_id | step_index | step_count |",
            "| --- | --- | --- | --- | --- | --- |"
        ])

        for record in onboardingRecords {
            let value = { (key: String) in
                record.parameters[key].map(describe) ?? "-"
            }

            lines.append(
                "| \(record.name) | \(value("flow_id")) | \(value("flow_version")) "
                    + "| \(value("step_id")) | \(value("step_index")) | \(value("step_count")) |"
            )
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func describe(_ value: TelemetryValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        }
    }
}

private func makeOnboardingDefaults() -> UserDefaults {
    let suiteName = "OnboardingAnalyticsFunnelTranscriptTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
