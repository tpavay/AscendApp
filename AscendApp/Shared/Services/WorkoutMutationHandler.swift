//
//  WorkoutMutationHandler.swift
//  AscendApp
//

import Foundation
import SwiftData
import FirebaseAuth

/// Centralized handler for post-workout-mutation side effects.
///
/// Every code path that creates, edits, deletes, or imports workouts should call
/// `workoutsDidChange(modelContext:newWorkouts:)` after the mutation is persisted.
/// This ensures PRs, leaderboard stats, and any future derived data stay in sync
/// without requiring each call site to know about every side effect.
@MainActor
final class WorkoutMutationHandler {
    static let shared = WorkoutMutationHandler()

    private let settingsManager = SettingsManager.shared
    private let leaderboardService = LeaderboardService.shared

    private init() {}

    /// Call after any workout create, edit, delete, or import has been saved to SwiftData.
    ///
    /// This method:
    /// 1. Recalculates all personal records (synchronous — updates UI immediately)
    /// 2. Recalculates local leaderboard stats for every time frame (skipped if not authenticated)
    /// 3. Applies newly created/imported workouts to the current active climb, if one exists
    ///
    /// - Parameter modelContext: The active SwiftData model context (must already have the mutation saved).
    /// - Parameter newWorkouts: Workouts that were newly created/imported as part of the mutation. Edited or deleted
    ///   workouts should not be passed here so climb progress only advances from brand-new sessions.
    func workoutsDidChange(modelContext: ModelContext, newWorkouts: [Workout] = []) throws {
        // 1. Recalculate personal records
        try PersonalRecordService.recalculateAllPersonalRecords(
            modelContext: modelContext,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )

        // 2. Advance the active climb from newly created/imported workouts only
        try ClimbService.shared.apply(workouts: newWorkouts, modelContext: modelContext)

        // 3. Recalculate local leaderboard stats (fresh fetch avoids @Query staleness)
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let allWorkouts = try modelContext.fetch(
            FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )
        leaderboardService.configure(modelContext: modelContext)
        try leaderboardService.updateAllTimeFrames(for: userId, workouts: allWorkouts)
    }
}
