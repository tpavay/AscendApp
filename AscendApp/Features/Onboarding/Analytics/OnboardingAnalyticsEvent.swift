import Foundation

struct OnboardingAnalyticsContext: Sendable, Hashable {
    static let flowID = "onboarding"

    /// The onboarding of 1.3.0: selling screens and setup, then sign-in, which is where the tracked flow ends.
    /// The paywall that follows for a climber without access is the app-access gate, a Superwall paywall.
    static let currentFlowVersion = "v3"
    /// The flow that ships while `onboarding_v3_enabled` is off. Every context the old screens
    /// build defaults to it, so switching the new flow on never relabels the old funnel.
    static let legacyFlowVersion = "v1"

    /// The v3 funnel, in order. Written out by hand on purpose and never derived from
    /// ``OnboardingV3Step``: `step_index` and `step_count` are what a funnel reads positions from, so
    /// a step added to the enum must be placed here deliberately or the index would silently
    /// develop a gap. `OnboardingV3KitTests.theHandWrittenFunnelOrderMatchesTheStepEnum` holds the
    /// two lists to the same members.
    ///
    /// Branches (`health_permission` and `health_history` on the Health path, `usual_climb` on the
    /// other) share one ordering; funnels read a branch by `step_id`.
    static let orderedStepIDs = [
        "welcome",
        "go_harder",
        "get_better",
        "something_to_chase",
        "count_methods",
        "health_connect",
        "health_permission",
        "health_history",
        "usual_climb",
        "climber_card",
        "claim_city",
        "weekly_target",
        "this_month_event",
        "notification_primer",
        "auth"
    ]

    /// The v1 funnel's order, kept only while the old flow still ships behind the v3 switch.
    static let legacyOrderedStepIDs = [
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
        "athlete",
        "age",
        "weight",
        "location",
        "notifications",
        "loading",
        "first_climb",
        "paywall"
    ]

    static func orderedStepIDs(forFlowVersion flowVersion: String) -> [String] {
        flowVersion == legacyFlowVersion ? legacyOrderedStepIDs : orderedStepIDs
    }

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
        flowVersion: String = Self.legacyFlowVersion,
        stepID: String
    ) {
        let canonicalStepIndex = Self.canonicalStepIndex(for: stepID, flowVersion: flowVersion)
        assert(canonicalStepIndex != nil, "Unknown onboarding analytics step: \(stepID)")

        self.segmentID = segmentID
        self.flowVersion = flowVersion
        self.stepID = stepID
        stepIndex = canonicalStepIndex ?? Self.unknownStepIndex
        stepCount = Self.orderedStepIDs(forFlowVersion: flowVersion).count
    }

    private init(segmentID: String, flowVersion: String, stepID: String, stepIndex: Int, stepCount: Int) {
        self.segmentID = segmentID
        self.flowVersion = flowVersion
        self.stepID = stepID
        self.stepIndex = stepIndex
        self.stepCount = stepCount
    }

    /// Where the paywall reports itself for a climber of `flowVersion`.
    ///
    /// The v1 flow ends on the paywall, so it has a position in its own list. The v3 flow ends at
    /// sign-in: the paywall a climber without access meets next is the app-access gate, a Superwall
    /// paywall configured in the dashboard, so it is not one of v3's steps. It still reports under the
    /// pass that led to it, one position past the last step (`step_index` equal to `step_count`), so
    /// a funnel filtered to `flow_version=v3` reads it as the hand-off it is without a step that
    /// does not exist ever entering ``orderedStepIDs``.
    static func paywallHandOff(flowVersion: String) -> OnboardingAnalyticsContext {
        guard flowVersion != legacyFlowVersion else { return OnboardingAnalyticsEvent.paywallContext }

        let count = orderedStepIDs(forFlowVersion: flowVersion).count
        return OnboardingAnalyticsContext(
            segmentID: OnboardingAnalyticsEvent.paywallContext.segmentID,
            flowVersion: flowVersion,
            stepID: OnboardingAnalyticsEvent.paywallContext.stepID,
            stepIndex: count,
            stepCount: count
        )
    }

    static func canonicalStepIndex(
        for stepID: String,
        flowVersion: String = Self.legacyFlowVersion
    ) -> Int? {
        orderedStepIDs(forFlowVersion: flowVersion).firstIndex(of: stepID)
    }
}

enum OnboardingFlowCompletionReason: String, Codable, Equatable, Sendable {
    case purchase
    case restore
    case existingEntitlement = "existing_entitlement"
    /// The climber declined every paid offer and was let in on the server-granted free week. Not a
    /// sale and not an entitlement: a later purchase reports as `free_week_purchase_completed`.
    case freeWeek = "free_week"
    /// Access arrived after the pass asked for it and nothing in the app confirmed how - a comp, a
    /// promotional grant, or a purchase made outside the app. Never counted as a sale.
    case unknown
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
    case screenViewed(context: OnboardingAnalyticsContext)
    case flowResumed(context: OnboardingAnalyticsContext)
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
    case signOutTapped(context: OnboardingAnalyticsContext, inputType: String)
    case signOutConfirmed(context: OnboardingAnalyticsContext)
    case notificationPermissionSelected(context: OnboardingAnalyticsContext, status: String)
    case firstClimbSelected(context: OnboardingAnalyticsContext, climbID: String, climbName: String)
    case authStarted(provider: String)
    case authCompleted(provider: String)
    case authFailed(provider: String, reason: String)
    case paywallReached(placement: String, source: String?, context: OnboardingAnalyticsContext = OnboardingAnalyticsEvent.paywallContext)
    case flowCompleted(context: OnboardingAnalyticsContext, completionReason: OnboardingFlowCompletionReason)

    var record: TelemetryRecord {
        switch self {
        case .flowStarted(let context, let resume):
            return makeRecord(
                name: "onboarding_flow_started",
                context: context,
                parameters: ["resume": .bool(resume)]
            )
        case .screenViewed(let context):
            return makeRecord(
                name: "onboarding_screen_viewed",
                context: context,
                parameters: [
                    "screen_id": .string(context.stepID),
                    "viewed": .bool(true)
                ]
            )
        case .flowResumed(let context):
            // A step reports its view once per pass, so an interrupted climber's return no longer
            // shows up as a re-emitted view. This is that signal, once per launch that resumes.
            return makeRecord(
                name: "onboarding_flow_resumed",
                context: context,
                parameters: ["screen_id": .string(context.stepID)]
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
        case .signOutTapped(let context, let inputType):
            // The opening screen's leading control is a sign-out, not a back tap, so it
            // reports as one: counting it as navigation would read as a climber moving
            // backwards through a flow that has nothing behind it.
            return makeRecord(
                name: "onboarding_sign_out_tapped",
                context: context,
                parameters: [
                    "from_step": .string(context.stepID),
                    "input_type": .string(inputType)
                ]
            )
        case .signOutConfirmed(let context):
            return makeRecord(
                name: "onboarding_sign_out_confirmed",
                context: context,
                parameters: ["from_step": .string(context.stepID)]
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
        case .paywallReached(let placement, let source, let context):
            var parameters: [String: TelemetryValue] = [
                "placement": .string(placement)
            ]

            if let source {
                parameters["source"] = .string(source)
            }

            return makeRecord(
                name: "onboarding_paywall_reached",
                context: context,
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
