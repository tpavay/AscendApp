//
//  BestEffortCacheSnapshot.swift
//  AscendApp
//
//  Created by Codex on 5/15/26.
//

import Foundation

struct BestEffortCacheSnapshot {
    private let rankedEntries: [BestEffortCacheEntry]
    private let progressionEntries: [BestEffortCacheEntry]
    private let workoutsByID: [UUID: Workout]

    init(entries: [BestEffortCacheEntry], workouts: [Workout]) {
        self.rankedEntries = entries.filter { $0.kind == .ranked }
        self.progressionEntries = entries.filter { $0.kind == .progression }
        self.workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
    }

    func board(
        scope: BestEffortScope,
        context: BestEffortContext
    ) -> BestEffortBoard {
        let efforts = rankedEntries
            .filter {
                $0.scopeRawValue == scope.rawValue
                    && $0.contextID == context.id
                    && $0.rank <= 3
            }
            .compactMap(rankedEffort)

        let categories = BestEffortMetric.allDefinitions.compactMap { metric -> BestEffortCategoryRanking? in
            let metricEfforts = efforts
                .filter { $0.metric == metric }
                .sorted { lhs, rhs in
                    if lhs.rank != rhs.rank {
                        return lhs.rank < rhs.rank
                    }
                    return lhs.id < rhs.id
                }

            guard !metricEfforts.isEmpty else { return nil }
            return BestEffortCategoryRanking(metric: metric, efforts: metricEfforts)
        }

        let sections = BestEffortSectionKind.allCases.compactMap { section -> BestEffortSection? in
            let sectionCategories = categories.filter { $0.metric.section == section }
            guard !sectionCategories.isEmpty else { return nil }
            return BestEffortSection(kind: section, categories: sectionCategories)
        }

        return BestEffortBoard(scope: scope, context: context, sections: sections)
    }

    func rankedEfforts(
        for metric: BestEffortMetric,
        scope: BestEffortScope = .allTime,
        context: BestEffortContext = .all
    ) -> [RankedBestEffort] {
        rankedEntries
            .filter {
                $0.metricID == metric.id
                    && $0.scopeRawValue == scope.rawValue
                    && $0.contextID == context.id
            }
            .compactMap(rankedEffort)
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return lhs.id < rhs.id
            }
    }

    func recordProgression(
        for metric: BestEffortMetric,
        scope: BestEffortScope = .allTime,
        context: BestEffortContext = .all
    ) -> [RankedBestEffort] {
        progressionEntries
            .filter {
                $0.metricID == metric.id
                    && $0.scopeRawValue == scope.rawValue
                    && $0.contextID == context.id
            }
            .compactMap(rankedEffort)
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return lhs.id < rhs.id
            }
    }

    func efforts(for workout: Workout) -> [RankedBestEffort] {
        let efforts = rankedEntries
            .filter { $0.workoutID == workout.id }
            .compactMap(rankedEffort)

        return BestEffortRankingBuilder.sortedForSignificance(efforts)
    }

    func primaryEffort(for workout: Workout) -> RankedBestEffort? {
        efforts(for: workout).first
    }

    func primaryEffortsByWorkoutID() -> [UUID: RankedBestEffort] {
        let efforts = rankedEntries.compactMap(rankedEffort)
        return BestEffortRankingBuilder.sortedForSignificance(efforts).reduce(into: [:]) { result, effort in
            result[effort.workout.id] = result[effort.workout.id] ?? effort
        }
    }

    private func rankedEffort(from entry: BestEffortCacheEntry) -> RankedBestEffort? {
        guard let workout = workoutsByID[entry.workoutID] else { return nil }
        return entry.rankedEffort(using: workout)
    }
}
