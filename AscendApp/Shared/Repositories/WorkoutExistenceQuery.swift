//
//  WorkoutExistenceQuery.swift
//  AscendApp
//

import Foundation
import SwiftData

/// Answers "does this workout still exist?" without pulling the workout - or the store - into
/// memory.
///
/// `Workout` stores its heart-rate time series inline in `heartRateData`, so any
/// `fetch(FetchDescriptor<Workout>())` materialises the entire heart-rate history of the
/// device. Callers that only need identity must never take that path (ASCEND-IOS-1K).
enum WorkoutExistenceQuery {
    /// The subset of `ids` that still has a row in the store.
    ///
    /// Uses `fetchCount`, which resolves in SQLite and materialises no `Workout` objects.
    static func existingIDs(among ids: Set<UUID>, in modelContext: ModelContext) throws -> Set<UUID> {
        var existing: Set<UUID> = []

        for id in ids {
            var descriptor = FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.id == id
                }
            )
            descriptor.fetchLimit = 1

            if try modelContext.fetchCount(descriptor) > 0 {
                existing.insert(id)
            }
        }

        return existing
    }
}
