import SwiftData
import SwiftUI

/// The detail screen's sync row, reading the one presentation the coordinator publishes.
///
/// A view of its own because of what it observes. The row has to re-derive on every completed sync
/// pass - the workout's status settles on `failed` after the first refusal and stops moving, so it
/// cannot be the only signal, and the climber would sit on a quiet `Syncing` row for a climb that
/// had actually stopped. But observing the coordinator inside `WorkoutDetailView`'s body made that
/// whole screen an observer of it, and that body builds `WorkoutDetailDerivedContent` - a 104 KB
/// heart-rate decode plus a pace-splits rebuild, roughly 13 ms against an 8 ms frame budget. Passes
/// fire from seven surfaces including foregrounding and connectivity changes, so that landed
/// mid-scroll. Reading it here keeps the observation inside a subtree that is cheap to rebuild.
///
/// Nothing here bootstraps the row. The presentation arrives already resolved from
/// `WorkoutSyncCoordinator.presentation(for:)` - a pure in-memory read of the same published state
/// the climbs-list badge reads, so the two surfaces cannot disagree about one climb. The row's
/// predecessor cached the presentation in `@State` starting at `.hidden` and moved it from its own
/// `.task`; a hidden row renders nothing, so nested in the detail screen's `spacing: 24` stack -
/// where the screen actually places it - the warning and its `TRY AGAIN` never appeared at all.
struct WorkoutSyncStatusSection: View {
    let workout: Workout
    let effectiveColorScheme: ColorScheme

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var syncCoordinator = WorkoutSyncCoordinator.shared

    var body: some View {
        WorkoutSyncStatusRow(
            presentation: syncCoordinator.presentation(for: workout),
            effectiveColorScheme: effectiveColorScheme,
            onRetry: retrySyncNow
        )
    }

    /// One tap, one attempt, unlimited. The control locks for the whole operation and comes back
    /// live on failure; the row keeps saying `Couldn't sync this climb` throughout.
    private func retrySyncNow() {
        guard let userId = workout.ownerUserId ?? authVM.user?.uid else { return }

        Task { @MainActor in
            let wasAttempted = await syncCoordinator.retryNow(
                workoutId: workout.id,
                modelContext: modelContext,
                currentUserId: userId
            )

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
