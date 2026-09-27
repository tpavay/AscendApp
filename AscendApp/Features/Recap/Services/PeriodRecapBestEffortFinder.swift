import Foundation
import SwiftData

/// The best efforts a climber set during a closed period, from the device's own Best
/// Efforts cache: every all-time #1 whose climb started inside the window.
///
/// No server aggregate backs this - the cache is already derived on the device - and the
/// read is bounded: the #1 entries, then only the handful of climbs they point at, never
/// the whole workout store (ASCEND-IOS-1K).
enum PeriodRecapBestEffortFinder {
    @MainActor
    static func bestEfforts(
        in periods: [LeaderboardPeriod],
        modelContext: ModelContext
    ) -> [String: [PeriodRecapBestEffort]] {
        let rankOne = 1
        let rankedKind = BestEffortCacheEntryKind.ranked.rawValue
        let entryDescriptor = FetchDescriptor<BestEffortCacheEntry>(
            predicate: #Predicate<BestEffortCacheEntry> { entry in
                entry.rank == rankOne && entry.kindRawValue == rankedKind
            }
        )
        guard let entries = try? modelContext.fetch(entryDescriptor), !entries.isEmpty else {
            return [:]
        }

        let workoutIDs = Array(Set(entries.map(\.workoutID)))
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workoutIDs.contains(workout.id)
            }
        )
        guard let workouts = try? modelContext.fetch(workoutDescriptor), !workouts.isEmpty else {
            return [:]
        }

        let snapshot = BestEffortCacheSnapshot(entries: entries, workouts: workouts)
        let records = BestEffortMetric.allDefinitions.compactMap { metric -> (Date, PeriodRecapBestEffort)? in
            guard let top = snapshot.rankedEfforts(for: metric).first else { return nil }
            return (top.workout.date, PeriodRecapBestEffort(title: metric.title, value: value(for: top)))
        }

        var byPeriod: [String: [PeriodRecapBestEffort]] = [:]
        for period in periods {
            let id = PeriodRecap.documentID(cadence: period.timeFrame, periodKey: period.key)
            let inPeriod = records.filter { period.contains($0.0) }.map(\.1)
            if !inPeriod.isEmpty {
                byPeriod[id] = inPeriod
            }
        }
        return byPeriod
    }

    private static func value(for effort: RankedBestEffort) -> String {
        switch effort.metric {
        case .longestClimb, .fastestStepTarget:
            BestEffortFormatting.clockTime(effort.performance.value)
        case .highestAverageSPM, .mostSteps, .mostStepsInTime:
            effort.valueText
        }
    }
}
