//
//  WorkoutListFilterState.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import Foundation

@MainActor
final class WorkoutListFilterState: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedSources: Set<WorkoutSource> = []
    @Published var stepsRange: ClosedRange<Double>? = nil
    @Published var dateRange: ClosedRange<Date>? = nil
    @Published var durationRange: ClosedRange<Double>? = nil
    
    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    var hasActiveFilters: Bool {
        !normalizedSearchText.isEmpty ||
        !selectedSources.isEmpty ||
        stepsRange != nil ||
        dateRange != nil ||
        durationRange != nil
    }
    
    var hasAdvancedFilters: Bool {
        !selectedSources.isEmpty ||
        stepsRange != nil ||
        dateRange != nil ||
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
    
    func resetAll() {
        searchText = ""
        selectedSources.removeAll()
        stepsRange = nil
        dateRange = nil
        durationRange = nil
    }
    
    func clearSources() {
        selectedSources.removeAll()
    }
    
    func clearSteps() {
        stepsRange = nil
    }
    
    func clearDates() {
        dateRange = nil
    }
    
    func clearDurations() {
        durationRange = nil
    }
    
    private func matchesSources(_ workout: Workout) -> Bool {
        selectedSources.isEmpty || selectedSources.contains(workout.source)
    }
    
    private func matchesStepsRange(_ workout: Workout) -> Bool {
        guard let range = stepsRange else { return true }
        guard let metricValue = workout.steps ?? workout.primaryMetricValue else { return false }
        return range.contains(Double(metricValue))
    }
    
    private func matchesDurationRange(_ workout: Workout) -> Bool {
        guard let range = durationRange else { return true }
        return range.contains(workout.duration)
    }
    
    private func matchesDateRange(_ workout: Workout) -> Bool {
        guard let range = dateRange else { return true }
        return workout.date >= range.lowerBound && workout.date <= range.upperBound
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
