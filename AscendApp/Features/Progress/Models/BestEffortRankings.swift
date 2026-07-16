//
//  BestEffortRankings.swift
//  AscendApp
//
//  Created by Codex on 5/10/26.
//

import Foundation

enum BestEffortScope: String, CaseIterable, Identifiable {
    case allTime
    case thisYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allTime:
            return "All-time"
        case .thisYear:
            return "This Year"
        }
    }

    func contains(_ date: Date, referenceDate: Date, calendar: Calendar) -> Bool {
        switch self {
        case .allTime:
            return true
        case .thisYear:
            return calendar.component(.year, from: date) == calendar.component(.year, from: referenceDate)
        }
    }

    func sentenceSuffix(for rank: Int) -> String {
        switch self {
        case .allTime:
            return rank == 1 ? "ever" : "all-time"
        case .thisYear:
            return "this year"
        }
    }
}

enum BestEffortContext: Hashable, Identifiable {
    case all
    case bodyweight
    case weighted
    case exactWeight(WeightLoadoutKey)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .bodyweight:
            return "bodyweight"
        case .weighted:
            return "weighted"
        case .exactWeight(let loadout):
            return "exactWeight-\(loadout.keyString)"
        }
    }

    static let baseContexts: [BestEffortContext] = [.all, .bodyweight, .weighted]

    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .bodyweight:
            return "Bodyweight"
        case .weighted:
            return "Weighted"
        case .exactWeight(let loadout):
            return loadout.displayName(unit: MeasurementSystem.imperial.weightAbbreviation)
        }
    }

    func includes(_ workout: Workout) -> Bool {
        switch self {
        case .all:
            return true
        case .bodyweight:
            return !workout.hasWeights
        case .weighted:
            return workout.hasWeights
        case .exactWeight(let loadout):
            return workout.weightLoadoutKey == loadout
        }
    }

    var significanceScore: Int {
        switch self {
        case .all:
            return 20
        case .bodyweight:
            return 10
        case .weighted:
            return 30
        case .exactWeight:
            return 40
        }
    }
}

enum BestEffortSectionKind: String, CaseIterable, Identifiable {
    case endurance
    case pace
    case timeWindows
    case stepBenchmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endurance:
            return "Endurance"
        case .pace:
            return "Pace"
        case .timeWindows:
            return "Time Windows"
        case .stepBenchmarks:
            return "Step Benchmarks"
        }
    }
}

enum BestEffortComparisonDirection {
    case higherIsBetter
    case lowerIsBetter
}

enum BestEffortMetric: Hashable, Identifiable {
    case mostSteps
    case longestClimb
    case highestAverageSPM
    case mostStepsInTime(minutes: Int)
    case fastestStepTarget(steps: Int)

    var id: String {
        switch self {
        case .mostSteps:
            return "mostSteps"
        case .longestClimb:
            return "longestClimb"
        case .highestAverageSPM:
            return "highestAverageSPM"
        case .mostStepsInTime(let minutes):
            return "mostStepsIn\(minutes)Min"
        case .fastestStepTarget(let steps):
            return "fastest\(steps)Steps"
        }
    }

    var title: String {
        switch self {
        case .mostSteps:
            return "Most Steps"
        case .longestClimb:
            return "Longest Climb"
        case .highestAverageSPM:
            return "Highest Average SPM"
        case .mostStepsInTime(let minutes):
            return "Most Steps in \(minutes) Min"
        case .fastestStepTarget(let steps):
            return "Fastest \(BestEffortFormatting.integer(steps)) Steps"
        }
    }

    var section: BestEffortSectionKind {
        switch self {
        case .mostSteps, .longestClimb:
            return .endurance
        case .highestAverageSPM:
            return .pace
        case .mostStepsInTime:
            return .timeWindows
        case .fastestStepTarget:
            return .stepBenchmarks
        }
    }

    var comparisonDirection: BestEffortComparisonDirection {
        switch self {
        case .fastestStepTarget:
            return .lowerIsBetter
        case .mostSteps, .longestClimb, .highestAverageSPM, .mostStepsInTime:
            return .higherIsBetter
        }
    }

    var requiresTimeline: Bool {
        switch self {
        case .mostStepsInTime, .fastestStepTarget:
            return true
        case .mostSteps, .longestClimb, .highestAverageSPM:
            return false
        }
    }

    var displayPriority: Int {
        switch self {
        case .mostSteps:
            return 10
        case .longestClimb:
            return 20
        case .highestAverageSPM:
            return 30
        case .fastestStepTarget(let steps):
            return 40 + steps / 1_000
        case .mostStepsInTime(let minutes):
            return 60 + minutes
        }
    }

    var significanceScore: Int {
        switch self {
        case .mostSteps:
            return 32
        case .longestClimb:
            return 30
        case .highestAverageSPM:
            return 24
        case .fastestStepTarget(let steps):
            return 34 + min(steps / 500, 26)
        case .mostStepsInTime(let minutes):
            return 32 + min(minutes / 5, 18)
        }
    }

    func sentencePhrase(context: BestEffortContext) -> String {
        let loadoutSuffix: String
        let qualifier: String
        switch context {
        case .all:
            qualifier = ""
            loadoutSuffix = ""
        case .bodyweight:
            qualifier = "bodyweight "
            loadoutSuffix = ""
        case .weighted:
            qualifier = "weighted "
            loadoutSuffix = ""
        case .exactWeight(let loadout):
            qualifier = ""
            loadoutSuffix = " with \(loadout.displayName(unit: MeasurementSystem.imperial.weightAbbreviation).lowercased())"
        }

        switch self {
        case .mostSteps:
            return "most \(qualifier)steps\(loadoutSuffix)"
        case .longestClimb:
            return "longest \(qualifier)climb\(loadoutSuffix)"
        case .highestAverageSPM:
            return "highest \(qualifier)average SPM\(loadoutSuffix)"
        case .mostStepsInTime(let minutes):
            return "most \(qualifier)steps in \(minutes) min\(loadoutSuffix)"
        case .fastestStepTarget(let steps):
            return "fastest \(qualifier)\(BestEffortFormatting.integer(steps)) steps\(loadoutSuffix)"
        }
    }

    static let timeWindowMinutes = [5, 10, 20, 30, 45, 60]
    static let stepTargets = [500, 1_000, 2_000, 3_000, 5_000, 10_000]

    static let workoutRecordDefinitions: [BestEffortMetric] = [
        .mostSteps,
        .longestClimb,
        .highestAverageSPM
    ]

    static var liveSplitDefinitions: [BestEffortMetric] {
        timeWindowMinutes.map { .mostStepsInTime(minutes: $0) }
            + stepTargets.map { .fastestStepTarget(steps: $0) }
    }

    static var allDefinitions: [BestEffortMetric] {
        workoutRecordDefinitions + liveSplitDefinitions
    }
}

struct BestEffortPerformance {
    let metric: BestEffortMetric
    let workout: Workout
    let value: Double
    let steps: Int?
    let duration: TimeInterval?
    let segmentStartElapsedSeconds: Int?
    let segmentEndElapsedSeconds: Int?

    var stepsPerMinute: Double? {
        guard let steps, let duration, duration > 0 else { return nil }
        return Double(steps) / (duration / 60.0)
    }
}

struct RankedBestEffort: Identifiable {
    let metric: BestEffortMetric
    let rank: Int
    let scope: BestEffortScope
    let context: BestEffortContext
    let performance: BestEffortPerformance

    var id: String {
        [
            metric.id,
            scope.rawValue,
            context.id,
            "\(rank)",
            performance.workout.id.uuidString,
            "\(performance.segmentStartElapsedSeconds ?? -1)",
            "\(performance.segmentEndElapsedSeconds ?? -1)"
        ].joined(separator: "-")
    }

    var workout: Workout {
        performance.workout
    }

    var sentence: String {
        let prefix = rank == 1 ? "" : "\(BestEffortFormatting.ordinal(rank)) "
        let phrase = metric.sentencePhrase(context: context)
        let suffix = scope.sentenceSuffix(for: rank)
        return BestEffortFormatting.capitalizedFirst("\(prefix)\(phrase) \(suffix)")
    }

    var valueText: String {
        switch metric {
        case .mostSteps, .mostStepsInTime:
            return "\(BestEffortFormatting.integer(Int(performance.value.rounded()))) steps"
        case .longestClimb:
            return BestEffortFormatting.duration(performance.value)
        case .highestAverageSPM:
            return "\(BestEffortFormatting.integer(Int(performance.value.rounded()))) SPM"
        case .fastestStepTarget:
            return BestEffortFormatting.clockTime(performance.value)
        }
    }

    var compactValueText: String {
        switch metric {
        case .mostSteps, .mostStepsInTime, .highestAverageSPM:
            return BestEffortFormatting.integer(Int(performance.value.rounded()))
        case .longestClimb:
            return BestEffortFormatting.clockTime(performance.value)
        case .fastestStepTarget:
            return BestEffortFormatting.clockTime(performance.value)
        }
    }

    var dateText: String {
        BestEffortFormatting.shortDate(performance.workout.date)
    }

    var categoryRowDetailText: String? {
        var parts: [String] = []

        if let start = performance.segmentStartElapsedSeconds,
           let end = performance.segmentEndElapsedSeconds {
            parts.append("\(BestEffortFormatting.clockTime(TimeInterval(start)))-\(BestEffortFormatting.clockTime(TimeInterval(end)))")
        }

        if let spm = performance.stepsPerMinute,
           case .fastestStepTarget = metric {
            parts.append("\(BestEffortFormatting.integer(Int(spm.rounded()))) SPM")
        }

        if let loadoutDetail = loadoutDetailText {
            parts.append(loadoutDetail)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    var detailText: String {
        var parts: [String] = []

        if let start = performance.segmentStartElapsedSeconds,
           let end = performance.segmentEndElapsedSeconds {
            parts.append("\(BestEffortFormatting.clockTime(TimeInterval(start)))-\(BestEffortFormatting.clockTime(TimeInterval(end)))")
        }

        if let spm = performance.stepsPerMinute, metric.requiresTimeline {
            parts.append("\(BestEffortFormatting.integer(Int(spm.rounded()))) SPM")
        }

        parts.append(BestEffortFormatting.shortDate(performance.workout.date))

        if let loadoutDetail = loadoutDetailText {
            parts.append(loadoutDetail)
        }

        return parts.joined(separator: " | ")
    }

    private var loadoutDetailText: String? {
        guard let loadout = performance.workout.weightLoadoutKey else { return nil }
        switch context {
        case .bodyweight:
            return nil
        case .all, .weighted, .exactWeight:
            return loadout.displayName(unit: MeasurementSystem.imperial.weightAbbreviation)
        }
    }
}

struct BestEffortCategoryRanking: Identifiable {
    let metric: BestEffortMetric
    let efforts: [RankedBestEffort]

    var id: String { metric.id }
}

struct BestEffortSection: Identifiable {
    let kind: BestEffortSectionKind
    let categories: [BestEffortCategoryRanking]

    var id: String { kind.rawValue }
}

struct BestEffortBoard {
    let scope: BestEffortScope
    let context: BestEffortContext
    let sections: [BestEffortSection]

    var allEfforts: [RankedBestEffort] {
        sections.flatMap { section in
            section.categories.flatMap(\.efforts)
        }
    }

    var primaryEffort: RankedBestEffort? {
        BestEffortRankingBuilder.sortedForSignificance(allEfforts).first
    }
}

enum BestEffortRankingBuilder {
    static func availableContexts(from workouts: [Workout]) -> [BestEffortContext] {
        let exactLoadouts = Set(workouts.compactMap(\.weightLoadoutKey))
            .sorted { lhs, rhs in
                if lhs.totalWeight != rhs.totalWeight {
                    return lhs.totalWeight < rhs.totalWeight
                }
                return lhs.keyString < rhs.keyString
            }
            .map(BestEffortContext.exactWeight)

        return BestEffortContext.baseContexts + exactLoadouts
    }

    static func board(
        from workouts: [Workout],
        scope: BestEffortScope,
        context: BestEffortContext,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> BestEffortBoard {
        let scopedWorkouts = workouts.filter { workout in
            scope.contains(workout.date, referenceDate: referenceDate, calendar: calendar)
                && context.includes(workout)
        }

        let categories = BestEffortMetric.allDefinitions.compactMap { metric -> BestEffortCategoryRanking? in
            let performances = scopedWorkouts.compactMap { performance(for: metric, workout: $0) }
            let ranked = rank(performances, metric: metric, scope: scope, context: context, limit: 3)
            guard !ranked.isEmpty else { return nil }
            return BestEffortCategoryRanking(metric: metric, efforts: ranked)
        }

        let sections = BestEffortSectionKind.allCases.compactMap { kind -> BestEffortSection? in
            let sectionCategories = categories.filter { $0.metric.section == kind }
            guard !sectionCategories.isEmpty else { return nil }
            return BestEffortSection(kind: kind, categories: sectionCategories)
        }

        return BestEffortBoard(scope: scope, context: context, sections: sections)
    }

    static func rankedEfforts(
        for metric: BestEffortMetric,
        from workouts: [Workout],
        scope: BestEffortScope = .allTime,
        context: BestEffortContext = .all,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        limit: Int? = nil
    ) -> [RankedBestEffort] {
        let scopedWorkouts = workouts.filter { workout in
            scope.contains(workout.date, referenceDate: referenceDate, calendar: calendar)
                && context.includes(workout)
        }
        let performances = scopedWorkouts.compactMap { performance(for: metric, workout: $0) }
        return rank(performances, metric: metric, scope: scope, context: context, limit: limit)
    }

    static func recordProgression(
        for metric: BestEffortMetric,
        from workouts: [Workout],
        scope: BestEffortScope = .allTime,
        context: BestEffortContext = .all,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [RankedBestEffort] {
        let scopedPerformances = workouts
            .filter { workout in
                scope.contains(workout.date, referenceDate: referenceDate, calendar: calendar)
                    && context.includes(workout)
            }
            .compactMap { performance(for: metric, workout: $0) }
            .sorted { lhs, rhs in
                if lhs.workout.date != rhs.workout.date {
                    return lhs.workout.date < rhs.workout.date
                }
                return lhs.workout.id.uuidString < rhs.workout.id.uuidString
            }

        var currentBest: BestEffortPerformance?
        var progression: [BestEffortPerformance] = []

        for performance in scopedPerformances {
            guard let best = currentBest else {
                currentBest = performance
                progression.append(performance)
                continue
            }

            if isBetter(performance, than: best, metric: metric) {
                currentBest = performance
                progression.append(performance)
            }
        }

        return progression.enumerated().map { index, performance in
            RankedBestEffort(
                metric: metric,
                rank: index + 1,
                scope: scope,
                context: context,
                performance: performance
            )
        }
    }

    static func efforts(
        for workout: Workout,
        from workouts: [Workout],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        contexts: [BestEffortContext]? = nil
    ) -> [RankedBestEffort] {
        let resolvedContexts = contexts ?? eligibleContexts(for: workout)
        let allEfforts = BestEffortScope.allCases.flatMap { scope in
            resolvedContexts.flatMap { context in
                board(
                    from: workouts,
                    scope: scope,
                    context: context,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
                .allEfforts
            }
        }

        let workoutEfforts = allEfforts.filter { $0.workout.id == workout.id }
        return sortedForSignificance(workoutEfforts)
    }

    static func primaryEffort(
        for workout: Workout,
        from workouts: [Workout],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> RankedBestEffort? {
        efforts(
            for: workout,
            from: workouts,
            referenceDate: referenceDate,
            calendar: calendar
        )
        .first
    }

    static func primaryEffortsByWorkoutID(
        from workouts: [Workout],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [UUID: RankedBestEffort] {
        let contexts = availableContexts(from: workouts)
        let allEfforts = BestEffortScope.allCases.flatMap { scope in
            contexts.flatMap { context in
                board(
                    from: workouts,
                    scope: scope,
                    context: context,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
                .allEfforts
            }
        }

        return sortedForSignificance(allEfforts).reduce(into: [:]) { result, effort in
            result[effort.workout.id] = result[effort.workout.id] ?? effort
        }
    }

    static func sortedForSignificance(_ efforts: [RankedBestEffort]) -> [RankedBestEffort] {
        efforts.sorted { lhs, rhs in
            let lhsScore = significanceScore(lhs)
            let rhsScore = significanceScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            if lhs.performance.workout.date != rhs.performance.workout.date {
                return lhs.performance.workout.date > rhs.performance.workout.date
            }

            return lhs.id < rhs.id
        }
    }

    private static func rank(
        _ performances: [BestEffortPerformance],
        metric: BestEffortMetric,
        scope: BestEffortScope,
        context: BestEffortContext,
        limit: Int?
    ) -> [RankedBestEffort] {
        let sorted = performances.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                switch metric.comparisonDirection {
                case .higherIsBetter:
                    return lhs.value > rhs.value
                case .lowerIsBetter:
                    return lhs.value < rhs.value
                }
            }

            return lhs.workout.date > rhs.workout.date
        }

        let rankedPerformances = limit.map { Array(sorted.prefix($0)) } ?? sorted

        return rankedPerformances.enumerated().map { index, performance in
            RankedBestEffort(
                metric: metric,
                rank: index + 1,
                scope: scope,
                context: context,
                performance: performance
            )
        }
    }

    private static func isBetter(
        _ lhs: BestEffortPerformance,
        than rhs: BestEffortPerformance,
        metric: BestEffortMetric
    ) -> Bool {
        switch metric.comparisonDirection {
        case .higherIsBetter:
            return lhs.value > rhs.value
        case .lowerIsBetter:
            return lhs.value < rhs.value
        }
    }

    private static func performance(for metric: BestEffortMetric, workout: Workout) -> BestEffortPerformance? {
        guard WorkoutPlausibilityPolicy.hasPlausibleTotals(workout) else { return nil }

        switch metric {
        case .mostSteps:
            guard workout.steps > 0 else { return nil }
            return BestEffortPerformance(
                metric: metric,
                workout: workout,
                value: Double(workout.steps),
                steps: workout.steps,
                duration: workout.duration,
                segmentStartElapsedSeconds: nil,
                segmentEndElapsedSeconds: nil
            )

        case .longestClimb:
            guard workout.duration > 0 else { return nil }
            return BestEffortPerformance(
                metric: metric,
                workout: workout,
                value: workout.duration,
                steps: workout.steps,
                duration: workout.duration,
                segmentStartElapsedSeconds: nil,
                segmentEndElapsedSeconds: nil
            )

        case .highestAverageSPM:
            guard let pace = workout.stepsPerMinute, pace > 0 else { return nil }
            return BestEffortPerformance(
                metric: metric,
                workout: workout,
                value: pace,
                steps: workout.steps,
                duration: workout.duration,
                segmentStartElapsedSeconds: nil,
                segmentEndElapsedSeconds: nil
            )

        case .mostStepsInTime(let minutes):
            return bestStepsWindowPerformance(minutes: minutes, workout: workout, metric: metric)

        case .fastestStepTarget(let steps):
            return fastestStepTargetPerformance(targetSteps: steps, workout: workout, metric: metric)
        }
    }

    private static func bestStepsWindowPerformance(
        minutes: Int,
        workout: Workout,
        metric: BestEffortMetric
    ) -> BestEffortPerformance? {
        let windowSeconds = minutes * 60
        guard Int(workout.duration.rounded(.down)) >= windowSeconds,
              let points = timelinePoints(for: workout) else {
            return nil
        }

        let maxStart = max(Int(workout.duration.rounded(.down)) - windowSeconds, 0)
        let candidates = candidateWindowStartTimes(points: points, windowSeconds: windowSeconds, maxStart: maxStart)

        var bestSteps = 0
        var bestStart = 0

        for start in candidates {
            let end = start + windowSeconds
            let startSteps = cumulativeSteps(at: TimeInterval(start), in: points)
            let endSteps = cumulativeSteps(at: TimeInterval(end), in: points)
            let steps = max(Int((endSteps - startSteps).rounded()), 0)
            if steps > bestSteps {
                bestSteps = steps
                bestStart = start
            }
        }

        guard bestSteps > 0 else { return nil }

        return BestEffortPerformance(
            metric: metric,
            workout: workout,
            value: Double(bestSteps),
            steps: bestSteps,
            duration: TimeInterval(windowSeconds),
            segmentStartElapsedSeconds: bestStart,
            segmentEndElapsedSeconds: bestStart + windowSeconds
        )
    }

    private static func fastestStepTargetPerformance(
        targetSteps: Int,
        workout: Workout,
        metric: BestEffortMetric
    ) -> BestEffortPerformance? {
        guard workout.steps >= targetSteps,
              let points = timelinePoints(for: workout),
              let finalSteps = points.last?.steps,
              finalSteps >= targetSteps else {
            return nil
        }

        let candidateStarts = candidateStepStarts(points: points, targetSteps: targetSteps, finalSteps: finalSteps)

        var bestDuration: TimeInterval?
        var bestStartElapsed: TimeInterval?
        var bestEndElapsed: TimeInterval?

        for startSteps in candidateStarts {
            guard let startElapsed = elapsedTime(forCumulativeSteps: startSteps, in: points),
                  let endElapsed = elapsedTime(forCumulativeSteps: startSteps + targetSteps, in: points) else {
                continue
            }

            let duration = endElapsed - startElapsed
            guard duration > 0 else { continue }

            if bestDuration == nil || duration < (bestDuration ?? duration) {
                bestDuration = duration
                bestStartElapsed = startElapsed
                bestEndElapsed = endElapsed
            }
        }

        guard let bestDuration,
              let bestStartElapsed,
              let bestEndElapsed else {
            return nil
        }

        return BestEffortPerformance(
            metric: metric,
            workout: workout,
            value: bestDuration,
            steps: targetSteps,
            duration: bestDuration,
            segmentStartElapsedSeconds: Int(bestStartElapsed.rounded()),
            segmentEndElapsedSeconds: Int(bestEndElapsed.rounded())
        )
    }

    private static func timelinePoints(for workout: Workout) -> [LiveClimbProgressPoint]? {
        guard let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout),
              let intervalSeconds = metadata.splitIntervalSeconds,
              intervalSeconds > 0,
              let splitSteps = metadata.splitSteps,
              !splitSteps.isEmpty else {
            return nil
        }

        let targetSteps = max(metadata.targetStepCount ?? workout.steps, workout.steps)
        let points = LiveClimbWorkoutSummaryData.progressPoints(for: workout, targetSteps: targetSteps)

        guard points.count > 2 else { return nil }
        return points
    }

    private static func candidateWindowStartTimes(
        points: [LiveClimbProgressPoint],
        windowSeconds: Int,
        maxStart: Int
    ) -> [Int] {
        var candidates = Set<Int>([0, maxStart])

        for point in points {
            candidates.insert(point.elapsedSeconds)
            candidates.insert(point.elapsedSeconds - windowSeconds)
        }

        return candidates
            .filter { $0 >= 0 && $0 <= maxStart }
            .sorted()
    }

    private static func candidateStepStarts(
        points: [LiveClimbProgressPoint],
        targetSteps: Int,
        finalSteps: Int
    ) -> [Int] {
        var candidates = Set<Int>([0])

        for point in points {
            candidates.insert(point.steps)
            candidates.insert(point.steps - targetSteps)
        }

        return candidates
            .filter { $0 >= 0 && $0 + targetSteps <= finalSteps }
            .sorted()
    }

    private static func cumulativeSteps(at elapsedSeconds: TimeInterval, in points: [LiveClimbProgressPoint]) -> Double {
        guard let firstPoint = points.first else { return 0 }

        if elapsedSeconds <= Double(firstPoint.elapsedSeconds) {
            return Double(firstPoint.steps)
        }

        for (previousPoint, nextPoint) in zip(points, points.dropFirst()) {
            guard elapsedSeconds <= Double(nextPoint.elapsedSeconds) else { continue }
            let intervalSeconds = max(Double(nextPoint.elapsedSeconds - previousPoint.elapsedSeconds), 1)
            let elapsedInInterval = elapsedSeconds - Double(previousPoint.elapsedSeconds)
            let progress = min(max(elapsedInInterval / intervalSeconds, 0), 1)
            return Double(previousPoint.steps) + (Double(nextPoint.steps - previousPoint.steps) * progress)
        }

        return Double(points.last?.steps ?? firstPoint.steps)
    }

    private static func elapsedTime(
        forCumulativeSteps targetSteps: Int,
        in points: [LiveClimbProgressPoint]
    ) -> TimeInterval? {
        guard let firstPoint = points.first else { return nil }

        if targetSteps <= firstPoint.steps {
            return TimeInterval(firstPoint.elapsedSeconds)
        }

        for (previousPoint, nextPoint) in zip(points, points.dropFirst()) {
            if targetSteps == previousPoint.steps {
                return TimeInterval(previousPoint.elapsedSeconds)
            }

            guard targetSteps <= nextPoint.steps else { continue }

            let stepDelta = nextPoint.steps - previousPoint.steps
            guard stepDelta > 0 else {
                continue
            }

            let progress = Double(targetSteps - previousPoint.steps) / Double(stepDelta)
            let elapsedDelta = Double(nextPoint.elapsedSeconds - previousPoint.elapsedSeconds) * progress
            return TimeInterval(Double(previousPoint.elapsedSeconds) + elapsedDelta)
        }

        if targetSteps <= (points.last?.steps ?? 0) {
            return TimeInterval(points.last?.elapsedSeconds ?? firstPoint.elapsedSeconds)
        }

        return nil
    }

    private static func significanceScore(_ effort: RankedBestEffort) -> Int {
        let rankScore = max(4 - effort.rank, 0) * 1_000
        let scopeScore: Int
        switch effort.scope {
        case .allTime:
            scopeScore = 120
        case .thisYear:
            scopeScore = 80
        }

        return rankScore + scopeScore + effort.context.significanceScore + effort.metric.significanceScore
    }

    private static func eligibleContexts(for workout: Workout) -> [BestEffortContext] {
        if let loadout = workout.weightLoadoutKey {
            return [.all, .weighted, .exactWeight(loadout)]
        }

        return [.all, .bodyweight]
    }
}

enum BestEffortFormatting {
    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if hours > 0 {
            return "\(hours) hr \(padded(minutes)) min"
        }

        return "\(minutes) min"
    }

    static func clockTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(padded(minutes)):\(padded(seconds))"
        }

        return "\(minutes):\(padded(seconds))"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func capitalizedFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }

    private static func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
