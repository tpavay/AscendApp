import SwiftData
import SwiftUI

/// The one way back into a session the previous process never finished, for every mode.
///
/// A draft younger than an hour is resumed without a question: the gap is credited as wall clock,
/// the sensor restarts, and the running session opens with `HeadphoneSessionResumeSheet` asking
/// for the machine's count. An older draft gets the recovery screen, led by the machine's count
/// and Save - never again by a Resume that silently drops the gap (2026-10-23). A session this
/// process already restarted - by the HealthKit relaunch, or one whose screen was lost to a tab
/// switch - is adopted rather than rebuilt. `docs/headphone-session-recovery.md` is the contract.
struct ActiveHeadphoneWorkoutRecoveryView: View {
    let draft: ActiveHeadphoneWorkoutDraft
    let onResolved: () -> Void
    var coordinator: HeadphoneSessionRecoveryCoordinator = .shared

    @Environment(\.modelContext) private var modelContext
    @State private var resumedLiveClimbViewModel: LiveClimbSessionViewModel?
    @State private var resumedRoutineViewModel: ActiveRoutineViewModel?
    @State private var resumedRoutine: Routine?
    @State private var assessment: HeadphoneSessionRecoveryAssessment?
    @State private var isResolving = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLogPromptAppear = false
    @State private var syncedStepCount = 0
    @FocusState private var isStepFieldFocused: Bool

    var body: some View {
        if let viewModel = resumedLiveClimbViewModel {
            NavigationStack {
                LiveClimbSessionView(viewModel: viewModel)
            }
        } else if let routineViewModel = resumedRoutineViewModel, let routine = resumedRoutine {
            ActiveRoutineView(viewModel: routineViewModel, routine: routine)
        } else if isResolving {
            Color.clear
                .themedBackground()
                .task { resolve() }
        } else {
            // Only this branch is the recovery screen: the other two hand off to a live
            // session and a routine, and each of those reports itself.
            recoveryPrompt
                .trackOnce(screen: .activeHeadphoneWorkoutRecovery)
        }
    }

    // MARK: - Resolution

    /// Decides what this draft becomes: an adopted running session, an automatic resume, or the
    /// recovery screen. Runs once, before anything is drawn.
    private func resolve() {
        defer { isResolving = false }

        if let resumption = coordinator.adopt(draftID: draft.id) {
            adopt(resumption.session)
            return
        }
        if let running = coordinator.runningSession(for: draft) {
            adopt(running)
            return
        }

        let assessment = coordinator.assess(draft)
        self.assessment = assessment
        coordinator.reportSessionLost(draft, assessment: assessment)

        guard assessment.plan == .autoResume else { return }

        do {
            let resumption = try coordinator.resume(draft, modelContext: modelContext, assessment: assessment)
            _ = coordinator.adopt(draftID: draft.id)
            adopt(resumption.session)
        } catch {
            errorMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_auto_resume_failed",
                level: .error,
                details: draft.diagnosticDetails.merging(["error": error.localizedDescription]) { current, _ in current }
            )
        }
    }

    private func adopt(_ session: HeadphoneSessionResumption.Session) {
        switch session {
        case .liveClimb(let viewModel):
            resumedLiveClimbViewModel = viewModel
        case .routine(let viewModel, let routine):
            resumedRoutine = routine
            resumedRoutineViewModel = viewModel
        }
    }

    // MARK: - Recovery screen

    private var recoveryPrompt: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.ascendCaution)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ascend stopped counting.")
                        .font(.montserratBold(size: 30))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(explanation)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            stepSyncSection

            VStack(spacing: 10) {
                recoveryButton(title: saveButtonTitle, style: .primary) {
                    Task {
                        await save()
                    }
                }
                .disabled(isSaving || effectiveStepCount <= 0)
                .opacity(effectiveStepCount <= 0 ? 0.55 : 1)

                if assessment?.climberEndedSession != true {
                    recoveryButton(title: "Resume Live", style: .secondary) {
                        resume()
                    }
                }

                recoveryButton(title: "Discard", style: .destructive) {
                    Task {
                        await discard()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        .interactiveDismissDisabled()
        .onAppear {
            if syncedStepCount == 0 {
                syncedStepCount = draft.steps
            }
            guard !didLogPromptAppear else { return }
            didLogPromptAppear = true
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_prompt_shown",
                level: .warning,
                details: draft.diagnosticDetails
            )
        }
    }

    /// Plain words for what happened, worded from the facts the launch could establish.
    private var explanation: String {
        let clock = Self.clockPhrase(draft.durationSeconds)
        if assessment?.climberEndedSession == true {
            return "You ended this \(sessionLabel) at \(draft.steps.formatted()) steps and \(clock), and Ascend closed before saving it. Enter the machine's count and save it, or discard it."
        }
        let gap = assessment.map(Self.gapPhrase) ?? "a while"
        let reason = assessment?.lossReason.climberFacingClause ?? HeadphoneSessionLossReason.unknown.climberFacingClause
        return "\(reason) \(gap) ago, at \(draft.steps.formatted()) steps and \(clock) into this \(sessionLabel). Enter the machine's count to credit the work and save it, keep going live, or discard it."
    }

    /// What saving a typed count does. A session the climber ended keeps the clock they stopped;
    /// only a session Ascend lost is credited the time since.
    static func stepSyncHint(steps: Int, climberEndedSession: Bool) -> String {
        if climberEndedSession {
            return "Saving credits \(steps.formatted()) steps at the time you ended it."
        }
        return "Saving credits \(steps.formatted()) steps and the time since Ascend stopped, with the gap recorded."
    }

    static func gapPhrase(_ assessment: HeadphoneSessionRecoveryAssessment) -> String {
        let minutes = max(assessment.gapMinutes, 1)
        if minutes >= 120 {
            let hours = minutes / 60
            return "\(hours) hours"
        }
        if minutes >= 60 {
            let remainder = minutes - 60
            return remainder == 0 ? "1 hour" : "1 hour \(remainder) min"
        }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    private static func clockPhrase(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    private var sessionLabel: String {
        switch draft.kind {
        case .liveClimb:
            return "climb"
        case .justClimb:
            return "session"
        case .routine:
            return "routine"
        }
    }

    private var effectiveStepCount: Int {
        max(syncedStepCount, 0)
    }

    private var stepCountDidChange: Bool {
        effectiveStepCount != draft.steps
    }

    private var hasReachedTarget: Bool {
        LiveClimbCompletionPolicy.isCompletion(
            steps: effectiveStepCount,
            targetStepCount: draft.targetStepCount
        )
    }

    private var saveButtonTitle: String {
        if isSaving {
            return "Saving..."
        }

        switch draft.kind {
        case .liveClimb:
            return hasReachedTarget ? "Save Climb" : "Save Attempt"
        case .justClimb:
            return "Save Session"
        case .routine:
            return "Save Routine"
        }
    }

    private var stepSyncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Machine's current steps")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.white.opacity(0.78))

                Spacer()

                Text("Last counted \(draft.steps.formatted())")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.48))
            }

            TextField("Steps", value: $syncedStepCount, format: .number)
                .keyboardType(.numberPad)
                .submitLabel(.done)
                .focused($isStepFieldFocused)
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(stepCountDidChange ? Color.ascendAccent.opacity(0.72) : .white.opacity(0.12), lineWidth: 1)
                )
                .accessibilityLabel("Machine's current steps")

            if stepCountDidChange {
                Text(Self.stepSyncHint(
                    steps: effectiveStepCount,
                    climberEndedSession: assessment?.climberEndedSession == true
                ))
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(Color.ascendAccent.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func resume() {
        isStepFieldFocused = false
        let correctedSteps = stepCountDidChange ? effectiveStepCount : nil
        let deltaSteps = effectiveStepCount - draft.steps

        AppDiagnosticsRecorder.shared.record(
            "active_headphone_recovery_resume_tapped",
            level: .warning,
            details: draft.diagnosticDetails
        )

        let assessment = assessment ?? coordinator.assess(draft)
        do {
            // The screen has already explained the gap, so the running session opens without
            // the inline notice; a typed count rides the one gap credit the resume makes.
            let resumption = try coordinator.resume(
                draft,
                modelContext: modelContext,
                assessment: assessment,
                correctedSteps: correctedSteps,
                showsNotice: false
            )
            _ = coordinator.adopt(draftID: draft.id)
            TelemetryManager.shared.track(
                HeadphoneSessionRecoveryAnalyticsEvent.sessionResumed(
                    mode: draft.kind,
                    gapSeconds: Int(assessment.gap.rounded(.down)),
                    lossReason: assessment.lossReason,
                    source: correctedSteps == nil ? .wallClock : .machine,
                    deltaSteps: correctedSteps == nil ? 0 : deltaSteps,
                    action: .promptResume
                )
            )
            adopt(resumption.session)
        } catch {
            errorMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_resume_failed",
                level: .error,
                details: draft.diagnosticDetails.merging(["error": error.localizedDescription]) { current, _ in current }
            )
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let assessment = assessment ?? coordinator.assess(draft)
            let deltaSteps = effectiveStepCount - draft.steps
            try syncDraftIfNeeded()
            let details = draft.diagnosticDetails
            coordinator.publishSessionEnd(for: draft, outcome: .saved)
            _ = try ActiveHeadphoneWorkoutDraftSaver.save(draft, modelContext: modelContext)
            await LiveClimbActivityManager.shared.end(sessionID: draft.sessionID, status: .finished)
            TelemetryManager.shared.track(
                HeadphoneSessionRecoveryAnalyticsEvent.sessionResumed(
                    mode: draft.kind,
                    gapSeconds: Int(assessment.gap.rounded(.down)),
                    lossReason: assessment.lossReason,
                    source: deltaSteps == 0 ? .wallClock : .machine,
                    deltaSteps: deltaSteps,
                    action: .promptSave
                )
            )
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_saved_attempt",
                level: .warning,
                details: details
            )
            onResolved()
        } catch {
            errorMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_save_failed",
                level: .error,
                details: draft.diagnosticDetails.merging(["error": error.localizedDescription]) { current, _ in current }
            )
        }
    }

    private func syncDraftIfNeeded() throws {
        isStepFieldFocused = false
        guard stepCountDidChange else { return }

        try coordinator.creditGap(
            to: draft,
            correctedSteps: effectiveStepCount,
            in: modelContext,
            at: Date()
        )
    }

    private func discard() async {
        do {
            let assessment = assessment ?? coordinator.assess(draft)
            let details = draft.diagnosticDetails
            coordinator.publishSessionEnd(for: draft, outcome: .discarded)
            try ActiveHeadphoneWorkoutDraftStore().delete(draft, in: modelContext)
            await LiveClimbActivityManager.shared.end(sessionID: draft.sessionID, status: .failed)
            TelemetryManager.shared.track(
                HeadphoneSessionRecoveryAnalyticsEvent.sessionResumed(
                    mode: draft.kind,
                    gapSeconds: Int(assessment.gap.rounded(.down)),
                    lossReason: assessment.lossReason,
                    source: .wallClock,
                    deltaSteps: 0,
                    action: .promptDiscard
                )
            )
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_discarded",
                level: .warning,
                details: details
            )
            onResolved()
        } catch {
            errorMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_discard_failed",
                level: .error,
                details: draft.diagnosticDetails.merging(["error": error.localizedDescription]) { current, _ in current }
            )
        }
    }

    private func recoveryButton(
        title: String,
        style: RecoveryButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.montserratBold(size: 15))
                .foregroundStyle(style.foregroundStyle)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(style.backgroundStyle)
                )
        }
        .buttonStyle(.plain)
    }

    /// A recovered Just Climb, drawn the way the climber last chose on the setup sheet.
    static func resumedJustClimb(
        from draft: ActiveHeadphoneWorkoutDraft,
        resumeNotice: HeadphoneSessionResumeNotice? = nil,
        defaults: UserDefaults = .standard
    ) -> LiveClimbSessionViewModel {
        let kind = draft.justClimbGoalKindRawValue.flatMap(JustClimbGoalKind.init(rawValue:)) ?? .open
        let goal = JustClimbGoal(
            kind: kind,
            durationMinutes: draft.justClimbDurationMinutes ?? JustClimbGoal.defaultDurationMinutes,
            stepCount: draft.justClimbStepCount ?? JustClimbGoal.defaultStepCount
        )
        return LiveClimbSessionViewModel(
            justClimbGoal: goal,
            experience: .remembered(in: defaults),
            liveActivitySessionID: draft.sessionID,
            recoveredDraft: draft,
            resumeNotice: resumeNotice
        )
    }
}

private enum RecoveryButtonStyle {
    case primary
    case secondary
    case destructive

    var foregroundStyle: Color {
        switch self {
        case .primary:
            return .black
        case .secondary:
            return .white
        case .destructive:
            return Color.red.opacity(0.95)
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .primary:
            return Color.ascendAccent
        case .secondary:
            return .white.opacity(0.11)
        case .destructive:
            return Color.red.opacity(0.12)
        }
    }
}
