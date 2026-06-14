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
    case screenCompleted(
        context: OnboardingAnalyticsContext,
        eventName: String,
        inputType: String,
        properties: [String: TelemetryValue]
    )
    case questionAnswered(
        context: OnboardingAnalyticsContext,
        eventName: String,
        questionID: String,
        inputType: String,
        selectionType: String?,
        answerID: String,
        answerIndex: Int?,
        properties: [String: TelemetryValue]
    )
    case backTapped(context: OnboardingAnalyticsContext)
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
        case .screenCompleted(let context, let eventName, let inputType, let properties):
            var parameters: [String: TelemetryValue] = [
                "screen_id": .string(context.stepID),
                "input_type": .string(inputType),
                "completed": .bool(true)
            ]

            properties.forEach { parameters[$0.key] = $0.value }

            return makeRecord(
                name: eventName,
                context: context,
                parameters: parameters
            )
        case .questionAnswered(
            let context,
            let eventName,
            let questionID,
            let inputType,
            let selectionType,
            let answerID,
            let answerIndex,
            let properties
        ):
            var parameters: [String: TelemetryValue] = [
                "question_id": .string(questionID),
                "screen_id": .string(context.stepID),
                "input_type": .string(inputType),
                "answer_id": .string(answerID),
                "has_answer": .bool(true)
            ]

            if let selectionType {
                parameters["selection_type"] = .string(selectionType)
            }

            if let answerIndex {
                parameters["answer_index"] = .int(answerIndex)
            }

            properties.forEach { parameters[$0.key] = $0.value }

            return makeRecord(
                name: eventName,
                context: context,
                parameters: parameters
            )
        case .backTapped(let context):
            return makeRecord(
                name: "onboarding_back_tapped",
                context: context
            )
        case .notificationPermissionSelected(let context, let status):
            return makeRecord(
                name: "notifications_inputted",
                context: context,
                parameters: [
                    "question_id": .string("notifications"),
                    "screen_id": .string(context.stepID),
                    "input_type": .string("permission_prompt"),
                    "selection_type": .string("single_select"),
                    "answer_id": .string(status),
                    "status": .string(status),
                    "has_answer": .bool(true)
                ]
            )
        case .firstClimbSelected(let context, let climbID, let climbName):
            return makeRecord(
                name: "first_climb_selected",
                context: context,
                parameters: [
                    "question_id": .string("first_climb"),
                    "screen_id": .string(context.stepID),
                    "input_type": .string("single_select"),
                    "selection_type": .string("single_select"),
                    "answer_id": .string(climbID),
                    "has_answer": .bool(true),
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
