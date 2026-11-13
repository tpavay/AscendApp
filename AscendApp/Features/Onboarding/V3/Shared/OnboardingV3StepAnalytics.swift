import Foundation

/// How a climber left a v3 step, the `action_id` of its `onboarding_screen_completed`.
///
/// A closed set on purpose: the funnel reads an exit by this id, so a new way out of a step is a new
/// case here and never a free string at a call site.
enum OnboardingV3Action: String, Sendable {
    /// The step's primary action.
    case `continue`
    /// A quiet "skip" exit on a step that has an answer to give.
    case skip
    /// The chrome back control; the step was left backwards.
    case back
    /// Welcome's "Already have an account? Sign in" shortcut to the sign-in screen.
    case alreadyHaveAccount = "already_have_account"
    /// Health held no stair stepper workouts, so the Health branch ended early.
    case noWorkoutsFound = "no_workouts_found"
}

/// What leaving a v3 step reports, built from the coordinator's state so no screen carries its own
/// copy of the rule.
///
/// Pure: the event shapes are tested without a view tree.
enum OnboardingV3StepAnalytics {
    /// The `onboarding_screen_completed` for leaving `step`. A back move reports
    /// `completed=false`, so a count of completions never includes a step the climber retreated from.
    static func completed(
        step: OnboardingV3Step,
        context: OnboardingAnalyticsContext,
        action: OnboardingV3Action,
        nextStep: OnboardingV3Step
    ) -> OnboardingAnalyticsEvent {
        var properties: [String: TelemetryValue] = [
            "action_id": .string(action.rawValue),
            "next_step_id": .string(nextStep.analyticsID)
        ]
        if action == .back {
            properties["completed"] = .bool(false)
        }
        return .screenCompleted(context: context, inputType: "button", properties: properties)
    }

    /// The answer a setup step gives when it is left forwards, or `nil` for a step that asks nothing
    /// (or whose answer has its own event: `health_history`, `health_permission`, the notification
    /// primer). Read from the answers the screen just wrote, so the event says what was saved.
    ///
    /// Every value is a bounded id or a boolean: never the typed name, the birthday, the height, the
    /// weight or the city itself.
    static func answer(
        step: OnboardingV3Step,
        answers: PreAuthOnboardingAnswers,
        action: OnboardingV3Action,
        context: OnboardingAnalyticsContext
    ) -> OnboardingAnalyticsEvent? {
        guard action != .back else { return nil }

        switch step {
        case .usualClimb:
            let choice = UsualClimbChoice.stored(
                steps: answers.usualClimbSteps,
                minutes: answers.usualClimbMinutes
            )
            // Health history writes numbers no row stores; those climbers are told apart from a
            // climber who picked a band.
            let answerID = choice?.rawValue ?? (answers.usualClimbMinutes == nil ? "none" : "from_health")
            return question(context, "usual_climb", answerID)

        case .profileSetup:
            let hasName = [answers.firstName, answers.lastName]
                .contains { ($0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty == false }
            return question(
                context,
                "climber_card",
                action == .skip ? "skipped" : "filled",
                [
                    "has_photo": .bool(answers.profilePhotoFileName != nil),
                    "has_name": .bool(hasName),
                    "has_gender": .bool(answers.gender != nil),
                    "has_birthday": .bool(answers.birthday != nil),
                    "has_height": .bool(answers.heightCm != nil),
                    "has_weight": .bool(answers.weightKg != nil)
                ]
            )

        case .claimCity:
            return question(context, "claim_city", answers.city == nil ? "skipped" : "claimed")

        case .weeklyTarget:
            guard let days = answers.weeklyTargetDays else {
                return question(context, "weekly_target", "skipped")
            }
            return question(context, "weekly_target", String(days), ["target_days": .int(days)])

        default:
            return nil
        }
    }

    private static func question(
        _ context: OnboardingAnalyticsContext,
        _ questionID: String,
        _ answerID: String,
        _ properties: [String: TelemetryValue] = [:]
    ) -> OnboardingAnalyticsEvent {
        .questionAnswered(
            context: context,
            questionID: questionID,
            inputType: "button",
            selectionType: "single_select",
            answerID: answerID,
            answerIndex: nil,
            properties: properties
        )
    }
}
