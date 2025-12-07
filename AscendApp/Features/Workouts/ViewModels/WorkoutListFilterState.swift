//
//  WorkoutListFilterState.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import Foundation

enum WorkoutSortOption: String, CaseIterable, Identifiable {
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case stepsHighest = "Steps (Highest)"
    case stepsLowest = "Steps (Lowest)"
    case durationLongest = "Duration (Longest)"
    case durationShortest = "Duration (Shortest)"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dateNewest, .dateOldest: return "calendar"
        case .stepsHighest, .stepsLowest: return "figure.stairs"
        case .durationLongest, .durationShortest: return "clock"
        }
    }

    func displayName(for metric: WorkoutMetric) -> String {
        switch self {
        case .dateNewest: return "Date (Newest)"
        case .dateOldest: return "Date (Oldest)"
        case .stepsHighest: return "\(metric.displayName) (Highest)"
        case .stepsLowest: return "\(metric.displayName) (Lowest)"
        case .durationLongest: return "Duration (Longest)"
        case .durationShortest: return "Duration (Shortest)"
        }
    }
}

@MainActor
final class WorkoutListFilterState: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedSources: Set<WorkoutSource> = []
    @Published var stepsRange: ClosedRange<Double>? = nil
    @Published var dateFilter: WorkoutDateFilter? = nil
    @Published var durationRange: ClosedRange<Double>? = nil
    @Published var sortOption: WorkoutSortOption = .dateNewest
    
    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    var hasActiveFilters: Bool {
        !normalizedSearchText.isEmpty ||
        !selectedSources.isEmpty ||
        stepsRange != nil ||
        dateFilter != nil ||
        durationRange != nil
    }
    
    var hasAdvancedFilters: Bool {
        !selectedSources.isEmpty ||
        stepsRange != nil ||
        dateFilter != nil ||
        durationRange != nil
    }
    
    func applyFilters(to workouts: [Workout]) -> [Workout] {
        workouts.filter { workout in
            matchesSources(workout) &&
            matchesStepsRange(workout) &&
            matchesDurationRange(workout) &&
            matchesDateRange(workout) &&
            matchesSearch(workout)
        }
    }

    func applySorting(to workouts: [Workout], preferredMetric: WorkoutMetric) -> [Workout] {
        switch sortOption {
        case .dateNewest:
            return workouts.sorted { $0.date > $1.date }
        case .dateOldest:
            return workouts.sorted { $0.date < $1.date }
        case .stepsHighest:
            return workouts.sorted { $0.metricValue(for: preferredMetric) > $1.metricValue(for: preferredMetric) }
        case .stepsLowest:
            return workouts.sorted { $0.metricValue(for: preferredMetric) < $1.metricValue(for: preferredMetric) }
        case .durationLongest:
            return workouts.sorted { $0.duration > $1.duration }
        case .durationShortest:
            return workouts.sorted { $0.duration < $1.duration }
        }
    }
    
    func resetAll() {
        searchText = ""
        selectedSources.removeAll()
        stepsRange = nil
        dateFilter = nil
        durationRange = nil
    }
    
    func clearSources() {
        selectedSources.removeAll()
    }
    
    func clearSteps() {
        stepsRange = nil
    }
    
    func clearDates() {
        dateFilter = nil
    }
    
    func clearDurations() {
        durationRange = nil
    }
    
    private func matchesSources(_ workout: Workout) -> Bool {
        selectedSources.isEmpty || selectedSources.contains(workout.source)
    }
    
    private func matchesStepsRange(_ workout: Workout) -> Bool {
        guard let range = stepsRange else { return true }
        let preferredMetric = SettingsManager.shared.preferredWorkoutMetric
        return range.contains(Double(workout.metricValue(for: preferredMetric)))
    }
    
    private func matchesDurationRange(_ workout: Workout) -> Bool {
        guard let range = durationRange else { return true }
        return range.contains(workout.duration)
    }
    
    private func matchesDateRange(_ workout: Workout) -> Bool {
        guard let filter = dateFilter else { return true }
        let upperBound = filter.end ?? .distantFuture
        return workout.date >= filter.start && workout.date <= upperBound
    }
    
    private func matchesSearch(_ workout: Workout) -> Bool {
        let query = normalizedSearchText
        guard !query.isEmpty else { return true }
        
        let targets = [
            workout.name.lowercased(),
            workout.notes.lowercased(),
            workout.source.displayName.lowercased()
        ]
        
        return targets.contains { $0.contains(query) }
    }
}

struct WorkoutDateFilter: Equatable {
    var start: Date
    var end: Date?
    var isRange: Bool { end != nil }
}
