import Foundation

enum RoutineReplayLeaderboardContextBuilder {
    static func context(for routine: Routine) -> LiveReplayLeaderboardContext {
        let targetSteps = guidedTargetSteps(for: routine)

        if routine.source.isTemplate,
           let templateId = routine.templateId,
           !templateId.isEmpty {
            return .routineTemplate(
                templateId: templateId,
                targetSteps: targetSteps
            )
        }

        return .routine(
            routineId: routine.id,
            targetSteps: targetSteps
        )
    }

    static func guidedTargetSteps(for routine: Routine) -> Int {
        let guidedSteps = routine.intervals.reduce(0.0) { total, interval in
            total + (Double(interval.mappedStepsPerMinute) * interval.duration / 60)
        }

        return max(Int(guidedSteps.rounded()), 1)
    }
}
