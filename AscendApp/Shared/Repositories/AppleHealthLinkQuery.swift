//
//  AppleHealthLinkQuery.swift
//  AscendApp
//

import Foundation
import SwiftData

/// Resolves "has this Apple Health record already been imported?" against only the records being
/// asked about.
///
/// The import path used to answer this from an in-memory index built by fetching every `Workout`
/// in the store, which put an unbounded main-thread scan on every Home entry and another one per
/// imported candidate (ASCEND-IOS-1K). A workout is linked to an Apple Health record two ways -
/// the `WorkoutSourceLink` row and the legacy `Workout.healthKitUUID` - and both are checked here
/// so the bounded queries stay behaviour-identical to the scan they replace.
enum AppleHealthLinkQuery {
    /// The subset of `externalRecordIDs` that already has a workout in the store.
    static func importedRecordIDs(
        among externalRecordIDs: Set<String>,
        in modelContext: ModelContext
    ) throws -> Set<String> {
        guard !externalRecordIDs.isEmpty else { return [] }

        let linkDescriptor = FetchDescriptor<WorkoutSourceLink>(
            predicate: #Predicate<WorkoutSourceLink> { link in
                externalRecordIDs.contains(link.externalRecordID)
            }
        )
        // `WorkoutSourceLink` rows are narrow, and the fetch is bounded by the IDs asked about.
        // `provider` is computed over a private raw value so it cannot appear in the predicate;
        // filtering the handful of returned rows in memory keeps the old provider check exactly.
        var imported = Set(
            try modelContext.fetch(linkDescriptor)
                .filter { $0.provider == .appleHealth && $0.workout != nil }
                .map(\.externalRecordID)
        )

        // `healthKitUUID` is the pre-source-link way a workout claims an Apple Health record. It
        // still has to be checked - the Firestore restore path writes `healthKitUUID` without
        // creating a link - but only for the records the link table did not already account for.
        // Without that subtraction, a fully-imported store would match every row here and this
        // would be the whole-store scan again in a different disguise.
        let unresolvedRecordIDs = externalRecordIDs.subtracting(imported)
        guard !unresolvedRecordIDs.isEmpty else { return imported }

        // SwiftData translates `contains` over an array of optionals, but crashes on a
        // nil-coalesced comparison - hence the optional-typed list. `propertiesToFetch` keeps the
        // rows that do match from dragging their inline heart-rate series along.
        let optionalRecordIDs: [String?] = Array(unresolvedRecordIDs)
        var legacyDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                optionalRecordIDs.contains(workout.healthKitUUID)
            }
        )
        legacyDescriptor.propertiesToFetch = [\.healthKitUUID]

        for workout in try modelContext.fetch(legacyDescriptor) {
            guard let healthKitUUID = workout.healthKitUUID else { continue }
            imported.insert(healthKitUUID)
        }

        return imported
    }

    /// The workout already carrying `externalRecordID`, if one exists.
    static func workout(
        forExternalRecordID externalRecordID: String,
        in modelContext: ModelContext
    ) throws -> Workout? {
        let linkDescriptor = FetchDescriptor<WorkoutSourceLink>(
            predicate: #Predicate<WorkoutSourceLink> { link in
                link.externalRecordID == externalRecordID
            }
        )
        let linkedWorkout = try modelContext.fetch(linkDescriptor)
            .first { $0.provider == .appleHealth && $0.workout != nil }?
            .workout
        if let linkedWorkout {
            return linkedWorkout
        }

        var legacyDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.healthKitUUID == externalRecordID
            }
        )
        legacyDescriptor.fetchLimit = 1

        return try modelContext.fetch(legacyDescriptor).first
    }
}
