import Foundation

struct OnboardingAnalyticsContext: Sendable, Hashable {
    static let currentFlowVersion = "v1"

    let flowID: String
    let flowVersion: String
    let stepID: String
    let stepIndex: Int
    let stepCount: Int

    init(
        flowID: String,
        flowVersion: String = Self.currentFlowVersion,
        stepID: String,
        stepIndex: Int,
        stepCount: Int
    ) {
        self.flowID = flowID
        self.flowVersion = flowVersion
        self.stepID = stepID
        self.stepIndex = stepIndex
        self.stepCount = stepCount
    }
}

enum OnboardingAnalyticsEvent: TelemetryEvent {
    static let authContext = OnboardingAnalyticsContext(
        flowID: "pre_auth_auth",
        stepID: "auth",
        stepIndex: 0,
        stepCount: 1
    )

    case flowStarted(context: OnboardingAnalyticsContext)
    case stepViewed(context: OnboardingAnalyticsContext)
    case screenViewed(context: OnboardingAnalyticsContext, property: String)
    case stepCompleted(context: OnboardingAnalyticsContext, actionID: String)
    case backTapped(context: OnboardingAnalyticsContext)
    case answerSelected(
        context: OnboardingAnalyticsContext,
        questionID: String,
        answerID: String,
        answerIndex: Int?
    )
    case notificationPermissionSelected(context: OnboardingAnalyticsContext, status: String)
    case firstClimbSelected(context: OnboardingAnalyticsContext, climbID: String, climbName: String)
    case authStarted(provider: String)
    case authCompleted(provider: String)
    case authFailed(provider: String, reason: String)
    case paywallReached(placement: String, source: String?)
    case flowCompleted(context: OnboardingAnalyticsContext)

    var record: TelemetryRecord {
        switch self {
        case .flowStarted(let context):
            return makeRecord(
                name: "onboarding_flow_started",
                context: context
            )
        case .stepViewed(let context):
            return makeRecord(
                name: "onboarding_step_viewed",
                context: context
            )
        case .screenViewed(let context, let property):
            return makeRecord(
                name: "screen_viewed",
                context: context,
                parameters: ["property": .string(property)]
            )
        case .stepCompleted(let context, let actionID):
            return makeRecord(
                name: "onboarding_step_completed",
                context: context,
                parameters: ["action_id": .string(actionID)]
            )
        case .backTapped(let context):
            return makeRecord(
                name: "onboarding_back_tapped",
                context: context
            )
        case .answerSelected(let context, let questionID, let answerID, let answerIndex):
            var parameters: [String: TelemetryValue] = [
                "question_id": .string(questionID),
                "answer_id": .string(answerID)
            ]

            if let answerIndex {
                parameters["answer_index"] = .int(answerIndex)
            }

            return makeRecord(
                name: "onboarding_answer_selected",
                context: context,
                parameters: parameters
            )
        case .notificationPermissionSelected(let context, let status):
            return makeRecord(
                name: "onboarding_notification_permission_selected",
                context: context,
                parameters: ["status": .string(status)]
            )
        case .firstClimbSelected(let context, let climbID, let climbName):
            return makeRecord(
                name: "onboarding_first_climb_selected",
                context: context,
                parameters: [
                    "climb_id": .string(climbID),
                    "climb_name": .string(climbName)
                ]
            )
        case .authStarted(let provider):
            return makeRecord(
                name: "onboarding_auth_started",
                context: Self.authContext,
                parameters: ["provider": .string(provider)]
            )
        case .authCompleted(let provider):
            return makeRecord(
                name: "onboarding_auth_completed",
                context: Self.authContext,
                parameters: ["provider": .string(provider)]
            )
        case .authFailed(let provider, let reason):
            return makeRecord(
                name: "onboarding_auth_failed",
                context: Self.authContext,
                parameters: [
                    "provider": .string(provider),
                    "reason": .string(reason)
                ]
            )
        case .paywallReached(let placement, let source):
            var parameters: [String: TelemetryValue] = [
                "flow_id": .string("post_auth_onboarding"),
                "flow_version": .string(OnboardingAnalyticsContext.currentFlowVersion),
                "step_id": .string("paywall"),
                "placement": .string(placement)
            ]

            if let source {
                parameters["source"] = .string(source)
            }

            return TelemetryRecord(
                name: "onboarding_paywall_reached",
                parameters: parameters
            )
        case .flowCompleted(let context):
            return makeRecord(
                name: "onboarding_flow_completed",
                context: context
            )
        }
    }

    private func makeRecord(
        name: String,
        context: OnboardingAnalyticsContext,
        parameters: [String: TelemetryValue] = [:]
    ) -> TelemetryRecord {
        var mergedParameters = context.parameters
        parameters.forEach { mergedParameters[$0.key] = $0.value }

        return TelemetryRecord(
            name: name,
            parameters: mergedParameters
        )
    }
}

private extension OnboardingAnalyticsContext {
    var parameters: [String: TelemetryValue] {
        [
            "flow_id": .string(flowID),
            "flow_version": .string(flowVersion),
            "step_id": .string(stepID),
            "step_index": .int(stepIndex),
            "step_count": .int(stepCount)
        ]
    }
}
