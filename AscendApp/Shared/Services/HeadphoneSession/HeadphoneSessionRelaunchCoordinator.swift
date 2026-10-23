import Foundation
import SwiftData

/// What happens when iOS relaunches Ascend for a workout the dead process left running.
///
/// Apple documents the relaunch for a crash; whether a jetsam kill or a reboot triggers it is not
/// documented and is measured on a device, not here (`docs/headphone-session-recovery.md`). When it
/// fires, this reattaches the `HKWorkoutSession`, folds any refused checkpoint back into the draft,
/// and - for a draft inside the automatic-resume window - restarts the session for its mode in the
/// background with no screen. `MainTabView` then finds the running session and shows it on the next
/// foreground. When it does not fire, the next foreground does the same work one step later.
@MainActor
final class HeadphoneSessionRelaunchCoordinator {
    static let shared = HeadphoneSessionRelaunchCoordinator()

    private(set) var lastSceneConnectionWasWorkoutRecovery = false

    private let backgroundSession: LiveClimbBackgroundSessionService
    private let recovery: HeadphoneSessionRecoveryCoordinator
    private let draftStore: ActiveHeadphoneWorkoutDraftStore
    private let containerRegistry: AppModelContainerRegistry
    private let diagnostics: AppDiagnosticsRecorder

    init(
        backgroundSession: LiveClimbBackgroundSessionService = .shared,
        recovery: HeadphoneSessionRecoveryCoordinator = .shared,
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        containerRegistry: AppModelContainerRegistry = .shared,
        diagnostics: AppDiagnosticsRecorder = .shared
    ) {
        self.backgroundSession = backgroundSession
        self.recovery = recovery
        self.draftStore = draftStore
        self.containerRegistry = containerRegistry
        self.diagnostics = diagnostics
    }

    func handleSceneConnection(isWorkoutRecovery: Bool) async {
        lastSceneConnectionWasWorkoutRecovery = isWorkoutRecovery
        diagnostics.record(
            "scene_connected",
            details: ["workout_recovery": isWorkoutRecovery ? "true" : "false"]
        )
        guard isWorkoutRecovery else { return }
        await resumeFromSystemRelaunch()
    }

    /// The relaunch path proper. Every step records what it found, because the whole point of
    /// this launch is that nobody is watching it.
    func resumeFromSystemRelaunch() async {
        await backgroundSession.recoverActiveWorkoutSessionIfAvailable()

        guard let container = containerRegistry.container else {
            diagnostics.record("headphone_session_relaunch_no_store", level: .error)
            return
        }

        let modelContext = container.mainContext
        let draft: ActiveHeadphoneWorkoutDraft?
        do {
            draft = try draftStore.activeDraft(in: modelContext)
        } catch {
            diagnostics.record(
                "headphone_session_relaunch_lookup_failed",
                level: .error,
                details: ["error": error.localizedDescription]
            )
            return
        }

        guard let draft else {
            diagnostics.record("headphone_session_relaunch_no_draft", level: .warning)
            return
        }

        let assessment = recovery.assess(draft)
        recovery.reportSessionLost(draft, assessment: assessment)
        diagnostics.record(
            "headphone_session_relaunched_by_system",
            level: .warning,
            details: draft.diagnosticDetails.merging([
                "gap_seconds": String(Int(assessment.gap.rounded(.down))),
                "plan": assessment.plan == .autoResume ? "auto_resume" : "prompt"
            ]) { current, _ in current }
        )

        guard assessment.plan == .autoResume else { return }

        do {
            try recovery.resume(draft, modelContext: modelContext, assessment: assessment)
        } catch {
            diagnostics.record(
                "headphone_session_relaunch_resume_failed",
                level: .error,
                details: draft.diagnosticDetails.merging(["error": error.localizedDescription]) { current, _ in current }
            )
        }
    }
}
