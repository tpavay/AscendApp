//
//  BestEffortCacheStore.swift
//  AscendApp
//
//  Created by Codex on 5/15/26.
//

import CryptoKit
import Foundation
import SwiftData

@MainActor
enum BestEffortCacheStore {
    static let currentVersion = 1
    private static let metadataID = "best-effort-cache"

    static func rebuildIfNeeded(
        modelContext: ModelContext,
        userId: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let workouts = try fetchWorkouts(modelContext: modelContext, userId: userId)
        let referenceYear = calendar.component(.year, from: referenceDate)
        let signature = workoutSignature(for: workouts, referenceYear: referenceYear)
        let metadata = try fetchMetadata(modelContext: modelContext)
        let entryCount = try modelContext.fetchCount(FetchDescriptor<BestEffortCacheEntry>())

        guard metadata?.cacheVersion == currentVersion,
              metadata?.workoutSignature == signature,
              metadata?.referenceYear == referenceYear,
              metadata?.entryCount == entryCount else {
            try rebuild(
                modelContext: modelContext,
                workouts: workouts,
                referenceDate: referenceDate,
                calendar: calendar,
                precomputedSignature: signature,
                referenceYear: referenceYear
            )
            return
        }
    }

    static func rebuild(
        modelContext: ModelContext,
        userId: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let workouts = try fetchWorkouts(modelContext: modelContext, userId: userId)
        let referenceYear = calendar.component(.year, from: referenceDate)
        try rebuild(
            modelContext: modelContext,
            workouts: workouts,
            referenceDate: referenceDate,
            calendar: calendar,
            precomputedSignature: workoutSignature(for: workouts, referenceYear: referenceYear),
            referenceYear: referenceYear
        )
    }

    static func rebuild(
        modelContext: ModelContext,
        workouts: [Workout],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let referenceYear = calendar.component(.year, from: referenceDate)
        try rebuild(
            modelContext: modelContext,
            workouts: workouts,
            referenceDate: referenceDate,
            calendar: calendar,
            precomputedSignature: workoutSignature(for: workouts, referenceYear: referenceYear),
            referenceYear: referenceYear
        )
    }

    private static func rebuild(
        modelContext: ModelContext,
        workouts: [Workout],
        referenceDate: Date,
        calendar: Calendar,
        precomputedSignature: String,
        referenceYear: Int
    ) throws {
        try deleteExistingCache(modelContext: modelContext)

        let generatedAt = Date()
        let contexts = BestEffortRankingBuilder.availableContexts(from: workouts)
        var entryCount = 0

        for scope in BestEffortScope.allCases {
            for context in contexts {
                let board = BestEffortRankingBuilder.board(
                    from: workouts,
                    scope: scope,
                    context: context,
                    referenceDate: referenceDate,
                    calendar: calendar
                )

                for effort in board.allEfforts {
                    modelContext.insert(
                        BestEffortCacheEntry(
                            kind: .ranked,
                            effort: effort,
                            generatedAt: generatedAt,
                            cacheVersion: currentVersion
                        )
                    )
                    entryCount += 1
                }

                for metric in BestEffortMetric.allDefinitions {
                    let progression = BestEffortRankingBuilder.recordProgression(
                        for: metric,
                        from: workouts,
                        scope: scope,
                        context: context,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )

                    for effort in progression {
                        modelContext.insert(
                            BestEffortCacheEntry(
                                kind: .progression,
                                effort: effort,
                                generatedAt: generatedAt,
                                cacheVersion: currentVersion
                            )
                        )
                        entryCount += 1
                    }
                }
            }
        }

        modelContext.insert(
            BestEffortCacheMetadata(
                id: metadataID,
                cacheVersion: currentVersion,
                workoutSignature: precomputedSignature,
                referenceYear: referenceYear,
                generatedAt: generatedAt,
                entryCount: entryCount
            )
        )

        try modelContext.save()
    }

    private static func fetchWorkouts(modelContext: ModelContext, userId: String?) throws -> [Workout] {
        if let userId {
            let descriptor = FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.ownerUserId == userId
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        }

        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private static func fetchMetadata(modelContext: ModelContext) throws -> BestEffortCacheMetadata? {
        var descriptor = FetchDescriptor<BestEffortCacheMetadata>(
            predicate: #Predicate { $0.id == metadataID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func deleteExistingCache(modelContext: ModelContext) throws {
        let entries = try modelContext.fetch(FetchDescriptor<BestEffortCacheEntry>())
        for entry in entries {
            modelContext.delete(entry)
        }

        let metadata = try modelContext.fetch(FetchDescriptor<BestEffortCacheMetadata>())
        for item in metadata {
            modelContext.delete(item)
        }
    }

    private static func workoutSignature(for workouts: [Workout], referenceYear: Int) -> String {
        let components = workouts
            .sorted { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }
            .map { workout in
                [
                    workout.id.uuidString,
                    "\(workout.date.timeIntervalSinceReferenceDate)",
                    "\(workout.duration)",
                    "\(workout.steps)",
                    workout.weightLoadoutKey?.id ?? "bodyweight",
                    workout.sourceMetadata ?? ""
                ].joined(separator: ";")
            }
            .joined(separator: "|")

        let payload = "v\(currentVersion)|year:\(referenceYear)|\(components)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
