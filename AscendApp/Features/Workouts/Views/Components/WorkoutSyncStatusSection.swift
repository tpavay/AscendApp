import SwiftData
import SwiftUI

/// The detail screen's sync row, with everything that drives it.
///
/// A view of its own because of what it observes. The row has to re-derive on every completed sync
/// pass - the workout's status settles on `failed` after the first refusal and stops moving, so it
/// cannot be the only signal, and the climber would sit on a quiet `Syncing` row for a climb that
/// had actually stopped. But reading the coordinator's pass counter inside `WorkoutDetailView`'s
/// body made that whole screen an observer of it, and that body builds
/// `WorkoutDetailDerivedContent` - a 104 KB heart-rate decode plus a pace-splits rebuild, roughly
/// 13 ms against an 8 ms frame budget. Passes fire from seven surfaces including foregrounding and
/// connectivity changes, so that landed mid-scroll.
///
/// Owning the state here keeps the observation and the presentation cache inside a subtree that is
/// cheap to rebuild, and leaves the screen's expensive derivation rebuilding exactly as often as it
/// did before the row existed.
struct WorkoutSyncStatusSection: View {
    let workout: Workout
    let effectiveColorScheme: ColorScheme

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var syncCoordinator = WorkoutSyncCoordinator.shared

    /// A render cache only. The coordinator owns the in-flight and climber-asked latches, so
    /// navigating away and back cannot lose them or contradict them.
    @State private var presentation: WorkoutSyncPresentation = .hidden

    var body: some View {
        WorkoutSyncStatusRow(
            presentation: presentation,
            effectiveColorScheme: effectiveColorScheme,
            onRetry: retrySyncNow
        )
        .task(id: workout.id) {
            refreshPresentation()
        }
        .onChange(of: workout.remoteSyncStatusRawValue) { _, _ in
            refreshPresentation()
        }
        // The same per-pass signal the list keys off, so the two surfaces cannot disagree about
        // one climb.
        .onChange(of: syncCoordinator.completedPassCount) { _, _ in
            refreshPresentation()
        }
    }

    private func refreshPresentation() {
        presentation = syncCoordinator.syncPresentation(
            for: workout,
            modelContext: modelContext
        )
    }

    /// One tap, one attempt, unlimited. The control locks for the whole operation and comes back
    /// live on failure; the row keeps saying `Couldn't sync this climb` throughout.
    private func retrySyncNow() {
        guard let userId = workout.ownerUserId ?? authVM.user?.uid else { return }

        Task { @MainActor in
            // The tap itself is the request, so the control locks immediately rather than waiting
            // for the pass to reach this workout.
            presentation = .couldNotSyncRetrying

            let wasAttempted = await syncCoordinator.retryNow(
                workoutId: workout.id,
                modelContext: modelContext,
                currentUserId: userId
            )

            refreshPresentation()
            // The acknowledgement that a retry ran and failed is the haptic plus the control
            // returning from SYNCING to TRY AGAIN. The row deliberately does not change, so it can
            // never read as a fresh problem or as success.
            //
            // A tap no pass ever read - backups killed, the pass cancelled, another account's
            // climb - gets no failure haptic. Nothing was refused, so saying so would be a lie,
            // and the control coming back live is the honest answer on its own.
            if workout.isSyncedToCloud {
                HapticsManager.shared.trigger(.success)
            } else if wasAttempted {
                HapticsManager.shared.trigger(.warning)
            }
        }
    }
}
