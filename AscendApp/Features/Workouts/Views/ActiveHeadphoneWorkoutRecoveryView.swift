import SwiftData
import SwiftUI

struct ActiveHeadphoneWorkoutRecoveryView: View {
    let draft: ActiveHeadphoneWorkoutDraft
    let onResolved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var resumedLiveClimbViewModel: LiveClimbSessionViewModel?
    @State private var resumedRoutine: Routine?
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
        } else if let routine = resumedRoutine {
            ActiveRoutineView(routine: routine, recoveredDraft: draft)
        } else {
            // Only this branch is the recovery screen: the other two hand off to a live
            // session and a routine, and each of those reports itself.
            recoveryPrompt
                .trackOnce(screen: .activeHeadphoneWorkoutRecovery)
        }
    }

    private var recoveryPrompt: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.ascendAccent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Resume live?")
                        .font(.montserratBold(size: 30))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("Ascend found an unfinished \(sessionLabel). Sync the machine's current steps, continue live, save it, or discard it.")
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            stepSyncSection

            VStack(spacing: 10) {
                recoveryButton(title: "Resume Live", style: .primary) {
                    resume()
                }

                recoveryButton(title: saveButtonTitle, style: .secondary) {
                    Task {
                        await save()
                    }
                }
                .disabled(isSaving || effectiveStepCount <= 0)
                .opacity(effectiveStepCount <= 0 ? 0.55 : 1)

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
                Text("Current steps")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.white.opacity(0.78))

                Spacer()

                Text("Last saved \(draft.steps.formatted())")
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

            if stepCountDidChange {
                Text("This will sync the recovery draft from \(draft.steps.formatted()) to \(effectiveStepCount.formatted()) steps.")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(Color.ascendAccent.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resume() {
        do {
            try syncDraftIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_recovery_step_sync_failed",
                level: .error,
                details: draft.diagnosticDetails.merging(["error": error.localizedDescription]) { current, _ in current }
            )
            return
        }

        AppDiagnosticsRecorder.shared.record(
            "active_headphone_recovery_resume_tapped",
            level: .warning,
            details: draft.diagnosticDetails
        )

        switch draft.kind {
        case .liveClimb:
            guard let climbId = draft.climbId,
                  let climb = try? ClimbService.shared.climb(for: climbId) else {
                errorMessage = "This climb is no longer available."
                AppDiagnosticsRecorder.shared.record(
                    "active_headphone_recovery_resume_failed",
                    level: .error,
                    details: draft.diagnosticDetails.merging(["reason": "missing_climb"]) { current, _ in current }
                )
                return
            }

            resumedLiveClimbViewModel = LiveClimbSessionViewModel(
                climb: climb,
                liveActivitySessionID: draft.sessionID,
                recoveredDraft: draft
            )

        case .justClimb:
            let kind = draft.justClimbGoalKindRawValue.flatMap(JustClimbGoalKind.init(rawValue:)) ?? .open
            let goal = JustClimbGoal(
                kind: kind,
                durationMinutes: draft.justClimbDurationMinutes ?? JustClimbGoal.defaultDurationMinutes,
                stepCount: draft.justClimbStepCount ?? JustClimbGoal.defaultStepCount
            )
            resumedLiveClimbViewModel = LiveClimbSessionViewModel(
                justClimbGoal: goal,
                liveActivitySessionID: draft.sessionID,
                recoveredDraft: draft
            )

        case .routine:
            guard let routine = fetchRoutine() else {
                errorMessage = "This routine is no longer available. Save the attempt or discard it."
                AppDiagnosticsRecorder.shared.record(
                    "active_headphone_recovery_resume_failed",
                    level: .error,
                    details: draft.diagnosticDetails.merging(["reason": "missing_routine"]) { current, _ in current }
                )
                return
            }
            resumedRoutine = routine
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try syncDraftIfNeeded()
            let details = draft.diagnosticDetails
            _ = try ActiveHeadphoneWorkoutDraftSaver.save(draft, modelContext: modelContext)
            await LiveClimbActivityManager.shared.end(sessionID: draft.sessionID, status: .finished)
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

        try ActiveHeadphoneWorkoutDraftStore().applyRecoveryStepSync(
            correctedSteps: effectiveStepCount,
            to: draft,
            in: modelContext
        )
    }

    private func discard() async {
        do {
            let details = draft.diagnosticDetails
            try ActiveHeadphoneWorkoutDraftStore().delete(draft, in: modelContext)
            await LiveClimbActivityManager.shared.end(sessionID: draft.sessionID, status: .failed)
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

    private func fetchRoutine() -> Routine? {
        guard let routineId = draft.routineId else { return nil }
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == routineId }
        )
        return try? modelContext.fetch(descriptor).first
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
