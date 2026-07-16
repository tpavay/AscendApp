//
//  BestEffortCacheEntry.swift
//  AscendApp
//
//  Created by Codex on 5/15/26.
//

import Foundation
import SwiftData

enum BestEffortCacheEntryKind: String {
    case ranked
    case progression
}

@Model
final class BestEffortCacheEntry {
    var id: String
    var kindRawValue: String
    var metricID: String
    var scopeRawValue: String
    var contextID: String
    var contextKindRawValue: String
    var rank: Int
    var workoutID: UUID
    var value: Double
    var steps: Int?
    var duration: TimeInterval?
    var segmentStartElapsedSeconds: Int?
    var segmentEndElapsedSeconds: Int?
    var generatedAt: Date
    var cacheVersion: Int
    var sortKey: String

    init(
        kind: BestEffortCacheEntryKind,
        effort: RankedBestEffort,
        generatedAt: Date,
        cacheVersion: Int
    ) {
        let contextKind = effort.context.cacheKindRawValue
        let entryID = [
            kind.rawValue,
            effort.metric.id,
            effort.scope.rawValue,
            effort.context.id,
            "\(effort.rank)",
            effort.workout.id.uuidString,
            "\(effort.performance.segmentStartElapsedSeconds ?? -1)",
            "\(effort.performance.segmentEndElapsedSeconds ?? -1)"
        ].joined(separator: "|")

        self.id = entryID
        self.kindRawValue = kind.rawValue
        self.metricID = effort.metric.id
        self.scopeRawValue = effort.scope.rawValue
        self.contextID = effort.context.id
        self.contextKindRawValue = contextKind
        self.rank = effort.rank
        self.workoutID = effort.workout.id
        self.value = effort.performance.value
        self.steps = effort.performance.steps
        self.duration = effort.performance.duration
        self.segmentStartElapsedSeconds = effort.performance.segmentStartElapsedSeconds
        self.segmentEndElapsedSeconds = effort.performance.segmentEndElapsedSeconds
        self.generatedAt = generatedAt
        self.cacheVersion = cacheVersion
        self.sortKey = [
            kind.rawValue,
            effort.scope.rawValue,
            effort.context.id,
            effort.metric.id,
            String(format: "%05d", effort.rank),
            effort.workout.id.uuidString
        ].joined(separator: "|")
    }

    var kind: BestEffortCacheEntryKind? {
        BestEffortCacheEntryKind(rawValue: kindRawValue)
    }

    func rankedEffort(using workout: Workout) -> RankedBestEffort? {
        guard let metric = BestEffortMetric.definition(for: metricID),
              let scope = BestEffortScope(rawValue: scopeRawValue),
              let context = BestEffortContext.cacheContext(
                kindRawValue: contextKindRawValue,
                id: contextID,
                workout: workout
              ) else {
            return nil
        }

        let performance = BestEffortPerformance(
            metric: metric,
            workout: workout,
            value: value,
            steps: steps,
            duration: duration,
            segmentStartElapsedSeconds: segmentStartElapsedSeconds,
            segmentEndElapsedSeconds: segmentEndElapsedSeconds
        )

        return RankedBestEffort(
            metric: metric,
            rank: rank,
            scope: scope,
            context: context,
            performance: performance
        )
    }
}

@Model
final class BestEffortCacheMetadata {
    var id: String
    var cacheVersion: Int
    var workoutSignature: String
    var referenceYear: Int
    var generatedAt: Date
    var entryCount: Int

    init(
        id: String,
        cacheVersion: Int,
        workoutSignature: String,
        referenceYear: Int,
        generatedAt: Date,
        entryCount: Int
    ) {
        self.id = id
        self.cacheVersion = cacheVersion
        self.workoutSignature = workoutSignature
        self.referenceYear = referenceYear
        self.generatedAt = generatedAt
        self.entryCount = entryCount
    }
}

private extension BestEffortContext {
    var cacheKindRawValue: String {
        switch self {
        case .all:
            return "all"
        case .bodyweight:
            return "bodyweight"
        case .weighted:
            return "weighted"
        case .exactWeight:
            return "exactWeight"
        }
    }

    static func cacheContext(
        kindRawValue: String,
        id: String,
        workout: Workout
    ) -> BestEffortContext? {
        switch kindRawValue {
        case "all":
            return id == BestEffortContext.all.id ? .all : nil
        case "bodyweight":
            return id == BestEffortContext.bodyweight.id ? .bodyweight : nil
        case "weighted":
            return id == BestEffortContext.weighted.id ? .weighted : nil
        case "exactWeight":
            guard let loadout = workout.weightLoadoutKey else { return nil }
            let context = BestEffortContext.exactWeight(loadout)
            return context.id == id ? context : nil
        default:
            return nil
        }
    }
}

extension BestEffortMetric {
    static func definition(for id: String) -> BestEffortMetric? {
        allDefinitions.first { $0.id == id }
    }
}
