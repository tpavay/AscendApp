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
        var recorder = OnboardingScreenViewRecorder()
        let steps = Self.funnelSteps

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
            telemetry: telemetry
        )
        monetization.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])
        monetization.presentPaywall(.appAccessGate, params: ["source": "paywall_placeholder_retry"])
        Self.paywallOutcomes.forEach { telemetry.track($0) }

        let records = sink.records
        let transcript = Self.transcript(
            records: records,
            orderedScreenIDs: steps.map(\.screenID) + ["paywall"]
        )
        print(transcript)

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

        for step in steps where step.isInteractive {
            let decisions = records.filter { record in
                record.name != "onboarding_screen_viewed"
                    && record.parameters["step_id"] == .string(step.screenID)
                    && !Self.subProperties(of: record).isEmpty
            }

            #expect(!decisions.isEmpty, "\(step.screenID) reports no decision with sub-properties")
        }
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
            .analyticsContexts(flowID: "post_auth_features")
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
            return surveyInteractions(for: stage, context: context) + [completed([:])]
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
                completed([:])
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
                completed([:])
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
            .purchaseControllerCompleted(productID: "ascend_yearly", outcome: "purchased"),
            .restoreControllerCompleted(outcome: "restored")
        ]
    }
}

// MARK: - Transcript rendering

private extension OnboardingAnalyticsFunnelTranscriptTests {
    static let contextParameterKeys: Set<String> = [
        "flow_id", "flow_version", "step_id", "step_index", "step_count",
        "screen_id", "app_environment"
    ]

    static func subProperties(of record: TelemetryRecord) -> [String: TelemetryValue] {
        record.parameters.filter { !contextParameterKeys.contains($0.key) }
    }

    static func transcript(
        records: [TelemetryRecord],
        orderedScreenIDs: [String]
    ) -> String {
        var lines = [
            "",
            "ONBOARDING FUNNEL TRANSCRIPT - events as delivered to MixpanelTelemetrySink",
            "",
            "| # | Screen | Flow | Event | Sub-properties |",
            "| --- | --- | --- | --- | --- |"
        ]

        for (index, screenID) in orderedScreenIDs.enumerated() {
            let screenRecords = records.filter { $0.parameters["step_id"] == .string(screenID) }

            for (recordIndex, record) in screenRecords.enumerated() {
                let subProperties = subProperties(of: record)
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(describe($0.value))" }
                    .joined(separator: ", ")
                var flowID = ""
                if case .string(let value)? = record.parameters["flow_id"] {
                    flowID = value
                }

                lines.append(
                    "| \(recordIndex == 0 ? String(index + 1) : "") "
                        + "| \(recordIndex == 0 ? screenID : "") "
                        + "| \(recordIndex == 0 ? flowID : "") "
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
