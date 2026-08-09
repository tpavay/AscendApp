//
//  InAppSensorWorkoutQuery.swift
//  AscendApp
//

import Foundation
import SwiftData

/// Fetches the in-app sensor workouts Apple Health enrichment can act on, without scanning the
/// whole store.
///
/// Enrichment only ever targets `.headphoneMotion` sessions - climbs Ascend recorded itself and
/// wants Apple Health's heart rate and calories for. Predicating on source is what keeps this
/// bounded by the climber's *in-app* history rather than by the size of the whole local store,
/// which for a long-standing account still holds records from before Ascend dropped importing
/// (ASCEND-IOS-1K).
enum InAppSensorWorkoutQuery {
    /// Every in-app sensor workout, oldest first.
    ///
    /// Deliberately not narrowed further, and this is the one place the fix stops short. Whether
    /// a workout still needs enrichment depends on `heartRateTimeSeries` decoding to something
    /// non-empty, which a store predicate cannot see inside `heartRateData`. Narrowing on the
    /// nullable metric columns would silently drop a workout whose series is present but decodes
    /// to empty - reachable today, because several write paths encode a series unconditionally
    /// (the live heart-rate buffer, restore) - and that workout would
    /// stop being retried. Callers keep their exact `needsAppleHealthEnrichment` check, so this
    /// stays a strict superset of the scan it replaced, with no change in enrichment semantics.
    ///
    /// The residual cost is therefore linear in the user's *in-app* session count rather than
    /// constant. That is the dimension that does not grow with Apple Health history, which is
    /// what ASCEND-IOS-1K scaled on. Making it constant means normalising an empty heart-rate
    /// series to `nil` at every write site first - a workout-model change, not a query change.
    ///
    /// One fetch per enrichment pass, linear in the climber's in-app session count.
    static func allInAppSensorWorkouts(in modelContext: ModelContext) throws -> [Workout] {
        let inAppSensorSourceRawValue = WorkoutSource.headphoneMotion.rawValue
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.sourceRawValue == inAppSensorSourceRawValue
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }
}
