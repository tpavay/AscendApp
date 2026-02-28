//
//  ImportCelebrationService.swift
//  AscendApp
//

import Foundation
import SwiftData

@MainActor
struct ImportCelebrationService {
    typealias CapturedGoal = (goal: Goal, progress: GoalProgress)

    private struct WeeklyGoalStats {
        let workouts: Int
        let durationMinutes: Int
        let steps: Int
        let floors: Int
        let verticalClimb: Int
        let verticalClimbUnit: String
    }

    private struct GoalCompletionMessageContext {
        let goalDescriptor: String
        let overTargetAmount: Int
    }

    private enum GoalCompletionMessageTemplate: CaseIterable {
        case saidWouldDid
        case lockedIn
        case promiseKept
        case noExcuses

        func message(context: GoalCompletionMessageContext) -> GoalCompletionMessage {
            switch self {
            case .saidWouldDid:
                return GoalCompletionMessage(
                    kicker: context.overTargetAmount > 0 ? "GOAL CRUSHED" : "GOAL COMPLETED",
                    line1: "You said you would,",
                    line2: "and you did."
                )
            case .lockedIn:
                return GoalCompletionMessage(
                    kicker: "LOCKED IN",
                    line1: "You stayed with the plan,",
                    line2: "and closed it out."
                )
            case .promiseKept:
                return GoalCompletionMessage(
                    kicker: "PROMISE KEPT",
                    line1: "Target set: \(context.goalDescriptor).",
                    line2: "Target handled."
                )
            case .noExcuses:
                return GoalCompletionMessage(
                    kicker: "NO EXCUSES",
                    line1: "Consistency showed up,",
                    line2: "and so did you."
                )
            }
        }
    }

    static func fetchAllWorkouts(modelContext: ModelContext) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>()
        return try modelContext.fetch(descriptor)
    }

    static func captureGoalSnapshot(
        modelContext: ModelContext,
        existingWorkouts: [Workout],
        referenceDate: Date = Date()
    ) -> CapturedGoal? {
        do {
            let goalService = GoalService(modelContext: modelContext)
            guard let goal = try goalService.getActiveGoal() else { return nil }
            let progress = GoalProgressService.calculateProgress(
                for: goal,
                from: existingWorkouts,
                at: referenceDate
            )
            return (goal: goal, progress: progress)
        } catch {
            return nil
        }
    }

    static func buildGoalData(
        preGoal: Goal,
        preProgress: GoalProgress,
        allWorkoutsAfterImport: [Workout],
        referenceDate: Date
    ) -> GoalCelebrationSnapshot {
        let weekInterval = GoalProgressService.weekInterval(for: preGoal, at: referenceDate)
        let weeklyWorkouts = allWorkoutsAfterImport.filter { weekInterval.contains($0.date) }
        let weeklyStats = buildWeeklyGoalStats(from: weeklyWorkouts)

        let postProgress = GoalProgressService.calculateProgress(
            for: preGoal,
            from: allWorkoutsAfterImport,
            at: referenceDate
        )
        let completionContext = buildGoalCompletionContext(
            goal: preGoal,
            postProgress: postProgress,
            weekStart: weekInterval.start,
            weeklyStats: weeklyStats
        )

        return GoalCelebrationSnapshot(
            goalId: preGoal.id,
            metric: preGoal.metric,
            target: preGoal.target,
            weekStartDate: weekInterval.start,
            weeklyWorkoutCount: weeklyStats.workouts,
            weeklyDurationMinutes: weeklyStats.durationMinutes,
            weeklySteps: weeklyStats.steps,
            weeklyFloors: weeklyStats.floors,
            weeklyVerticalClimb: weeklyStats.verticalClimb,
            weeklyVerticalClimbUnit: weeklyStats.verticalClimbUnit,
            previousPercent: preProgress.percent,
            newPercent: postProgress.percent,
            previousCurrent: preProgress.current,
            newCurrent: postProgress.current,
            goalCompleted: preProgress.percent < 1.0 && postProgress.percent >= 1.0,
            formattedTarget: formattedTarget(for: preGoal),
            completionContext: completionContext
        )
    }

    private static func buildWeeklyGoalStats(from workouts: [Workout]) -> WeeklyGoalStats {
        let settings = SettingsManager.shared
        let totalDurationSeconds = workouts.reduce(0.0) { $0 + $1.duration }
        let durationMinutes = Int(totalDurationSeconds / 60.0)
        let steps = workouts.reduce(0) { $0 + $1.steps }
        let floors = workouts.reduce(0) { $0 + $1.floors }
        let verticalClimbTotal = workouts.reduce(0.0) { partial, workout in
            partial + workout.totalVerticalClimb(
                stepHeight: settings.stepHeight,
                measurementSystem: settings.measurementSystem
            )
        }

        return WeeklyGoalStats(
            workouts: workouts.count,
            durationMinutes: durationMinutes,
            steps: steps,
            floors: floors,
            verticalClimb: Int(verticalClimbTotal.rounded()),
            verticalClimbUnit: settings.measurementSystem.distanceUnit
        )
    }

    private static func buildGoalCompletionContext(
        goal: Goal,
        postProgress: GoalProgress,
        weekStart: Date,
        weeklyStats: WeeklyGoalStats
    ) -> GoalCompletionContext {
        let context = GoalCompletionMessageContext(
            goalDescriptor: formattedTarget(for: goal),
            overTargetAmount: max(0, postProgress.current - goal.target)
        )
        let template = pickMessageTemplate(goalId: goal.id, weekStart: weekStart, progressValue: postProgress.current)
        let supportingMetrics = buildSupportingMetrics(goalMetric: goal.metric, weeklyStats: weeklyStats)

        return GoalCompletionContext(
            message: template.message(context: context),
            supportingMetrics: supportingMetrics
        )
    }

    private static func pickMessageTemplate(goalId: UUID, weekStart: Date, progressValue: Int) -> GoalCompletionMessageTemplate {
        let source = "\(goalId.uuidString)-\(Int(weekStart.timeIntervalSince1970))-\(progressValue)"
        let seed = source.unicodeScalars.reduce(0) { partial, scalar in
            ((partial * 31) + Int(scalar.value)) & 0x7fffffff
        }
        let templates = GoalCompletionMessageTemplate.allCases
        let index = seed % templates.count
        return templates[index]
    }

    private static func buildSupportingMetrics(
        goalMetric: GoalMetric,
        weeklyStats: WeeklyGoalStats
    ) -> [GoalCompletionMetric] {
        let excludedKind = metricKind(for: goalMetric)
        let orderedKinds: [GoalCompletionMetric.Kind] = [.workouts, .duration, .steps, .floors, .verticalClimb]

        return orderedKinds.compactMap { kind in
            guard kind != excludedKind else { return nil }

            let payload = metricPayload(for: kind, weeklyStats: weeklyStats)
            guard payload.value > 0 else { return nil }

            return GoalCompletionMetric(
                kind: kind,
                iconName: payload.icon,
                value: payload.value,
                label: payload.label
            )
        }
        .prefix(3)
        .map { $0 }
    }

    private static func metricKind(for goalMetric: GoalMetric) -> GoalCompletionMetric.Kind {
        switch goalMetric {
        case .workouts: return .workouts
        case .duration: return .duration
        case .steps: return .steps
        case .floors: return .floors
        }
    }

    private static func metricPayload(
        for kind: GoalCompletionMetric.Kind,
        weeklyStats: WeeklyGoalStats
    ) -> (value: Int, label: String, icon: String) {
        switch kind {
        case .workouts:
            let label = weeklyStats.workouts == 1 ? "workout" : "workouts"
            return (weeklyStats.workouts, label, "figure.run")
        case .duration:
            let label = weeklyStats.durationMinutes == 1 ? "minute" : "minutes"
            return (weeklyStats.durationMinutes, label, "stopwatch")
        case .steps:
            return (weeklyStats.steps, "steps", "figure.stairs")
        case .floors:
            let label = weeklyStats.floors == 1 ? "floor" : "floors"
            return (weeklyStats.floors, label, "building.2")
        case .verticalClimb:
            return (weeklyStats.verticalClimb, weeklyStats.verticalClimbUnit, "arrow.up")
        }
    }

    private static func formattedTarget(for goal: Goal) -> String {
        let unit = goal.target == 1 ? goal.metric.unitSingular : goal.metric.unit
        return "\(goal.target.formatted()) \(unit)"
    }
}
