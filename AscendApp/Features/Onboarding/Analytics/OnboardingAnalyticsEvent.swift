import Foundation

struct OnboardingAnalyticsContext: Sendable, Hashable {
    static let flowID = "onboarding"
    static let currentFlowVersion = "v1"
    static let orderedStepIDs = [
        "welcome",
        "watch_yourself_get_better",
        "reason_to_come_back",
        "auth",
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
    ]

    /// The index reported for a step that is not part of the canonical flow. Contexts are built
    /// from content arrays, so an added carousel page or guide screen can drift out of the ordered
    /// list - and onboarding is the one flow a user has no way around, so instrumentation drift
    /// must never be able to terminate the app. Drift fails loudly in development and degrades to
    /// an out-of-band index in production instead.
    static let unknownStepIndex = -1

    let segmentID: String
    let flowVersion: String
    let stepID: String
    let stepIndex: Int
    let stepCount: Int

    init(
        segmentID: String,
        flowVersion: String = Self.currentFlowVersion,
        stepID: String
    ) {
        let canonicalStepIndex = Self.canonicalStepIndex(for: stepID)
        assert(canonicalStepIndex != nil, "Unknown onboarding analytics step: \(stepID)")

        self.segmentID = segmentID
        self.flowVersion = flowVersion
        self.stepID = stepID
        stepIndex = canonicalStepIndex ?? Self.unknownStepIndex
        stepCount = Self.orderedStepIDs.count
    }

    static func canonicalStepIndex(for stepID: String) -> Int? {
        orderedStepIDs.firstIndex(of: stepID)
    }
}

enum OnboardingFlowCompletionReason: String, Codable, Equatable, Sendable {
    case purchase
    case restore
    case existingEntitlement = "existing_entitlement"
}

enum OnboardingAnalyticsEvent: TelemetryEvent {
    static let welcomeContext = OnboardingAnalyticsContext(
        segmentID: "pre_auth_welcome",
        stepID: "welcome"
    )

    static let authContext = OnboardingAnalyticsContext(
        segmentID: "pre_auth_auth",
        stepID: "auth"
    )

    static let paywallContext = OnboardingAnalyticsContext(
        segmentID: PostAuthOnboardingStage.segmentID,
        stepID: "paywall"
    )

    case flowStarted(context: OnboardingAnalyticsContext, resume: Bool)
    case screenViewed(context: OnboardingAnalyticsContext, resume: Bool = false)
    case screenCompleted(
        context: OnboardingAnalyticsContext,
        inputType: String,
        properties: [String: TelemetryValue]
    )
    case questionAnswered(
        context: OnboardingAnalyticsContext,
        questionID: String,
        inputType: String,
        selectionType: String?,
        answerID: String,
        answerIndex: Int?,
        properties: [String: TelemetryValue]
    )
    case backTapped(context: OnboardingAnalyticsContext, inputType: String)
    case notificationPermissionSelected(context: OnboardingAnalyticsContext, status: String)
    case firstClimbSelected(context: OnboardingAnalyticsContext, climbID: String, climbName: String)
    case authStarted(provider: String)
    case authCompleted(provider: String)
    case authFailed(provider: String, reason: String)
    case paywallReached(placement: String, source: String?)
    case flowCompleted(context: OnboardingAnalyticsContext, completionReason: OnboardingFlowCompletionReason)

    var record: TelemetryRecord {
        switch self {
        case .flowStarted(let context, let resume):
            return makeRecord(
                name: "onboarding_flow_started",
                context: context,
                parameters: ["resume": .bool(resume)]
            )
        case .screenViewed(let context, let resume):
            return makeRecord(
                name: "onboarding_screen_viewed",
                context: context,
                parameters: [
                    "screen_id": .string(context.stepID),
                    "resume": .bool(resume),
                    "viewed": .bool(true)
                ]
            )
        case .screenCompleted(let context, let inputType, let properties):
            var parameters: [String: TelemetryValue] = [
                "screen_id": .string(context.stepID),
                "input_type": .string(inputType),
                "completed": .bool(true)
            ]

            properties.forEach { parameters[$0.key] = $0.value }

            return makeRecord(
                name: "onboarding_screen_completed",
                context: context,
                parameters: parameters
            )
        case .questionAnswered(
            let context,
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
                name: "onboarding_question_answered",
                context: context,
                parameters: parameters
            )
        case .backTapped(let context, let inputType):
            // `step_id` alone is ambiguous on a back tap, so name the step being left explicitly,
            // and `input_type` separates chrome taps from backward swipes.
            return makeRecord(
                name: "onboarding_back_tapped",
                context: context,
                parameters: [
                    "from_step": .string(context.stepID),
                    "input_type": .string(inputType)
                ]
            )
        case .notificationPermissionSelected(let context, let status):
            return makeRecord(
                name: "onboarding_question_answered",
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
                name: "onboarding_question_answered",
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
                "placement": .string(placement)
            ]

            if let source {
                parameters["source"] = .string(source)
            }

            return makeRecord(
                name: "onboarding_paywall_reached",
                context: Self.paywallContext,
                parameters: parameters
            )
        case .flowCompleted(let context, let completionReason):
            return makeRecord(
                name: "onboarding_flow_completed",
                context: context,
                parameters: ["completion_reason": .string(completionReason.rawValue)]
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
            "flow_id": .string(Self.flowID),
            "flow_version": .string(flowVersion),
            "segment_id": .string(segmentID),
            "step_id": .string(stepID),
            "step_index": .int(stepIndex),
            "step_count": .int(stepCount)
        ]
    }
}
