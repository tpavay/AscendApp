//
//  ImportCelebrationViewModel.swift
//  AscendApp
//

import SwiftUI
import UIKit

@MainActor
@Observable
class ImportCelebrationViewModel {

    // MARK: - Phase

    enum Phase {
        case appearing
        case countingStats
        case settled
    }

    /// Strict priority ordering for layout stability
    enum StatType: Int, CaseIterable, Sendable {
        case duration = 0
        case steps = 1
        case floors = 2
        case verticalClimb = 3
    }

    struct StatItem: Identifiable {
        let type: StatType
        let value: Int
        let label: String

        var id: Int { type.rawValue }
    }

    // MARK: - State

    let data: ImportCelebrationData
    var phase: Phase = .appearing
    var titleOpacity: Double = 0
    var statOpacities: [StatType: Double] = [:]
    var statProgress: [StatType: Double] = [:]  // 0→1 per stat for count-up
    var buttonOpacity: Double = 0
    var statGridScale: CGFloat = 1.0
    var heroScale: CGFloat = 1.0
    var showGoalSection = false
    var goalSectionOpacity: Double = 0
    var goalBarProgress: Double = 0
    var showGoalCompletionScreen = false

    private var animationTask: Task<Void, Never>?

    // MARK: - Init

    init(data: ImportCelebrationData) {
        self.data = data
        goalBarProgress = data.goalSnapshot?.previousPercent ?? 0

        // Initialize all stat opacities to 0
        for stat in visibleStats {
            statOpacities[stat.type] = 0
            statProgress[stat.type] = 0
        }
    }

    // MARK: - Computed

    var titleText: String {
        if data.importedCount == 1 {
            return "Workout Imported!"
        } else {
            return "\(data.importedCount) Workouts Imported!"
        }
    }

    var subtitleText: String? {
        guard data.hasPartialFailure else { return nil }
        return "Imported \(data.importedCount) of \(data.totalCount) workouts"
    }

    var goalSnapshot: GoalCelebrationSnapshot? {
        data.goalSnapshot
    }

    var visibleStats: [StatItem] {
        var items: [StatItem] = []

        let durationMinutes = Int(data.totalDuration / 60)
        if durationMinutes > 0 {
            items.append(StatItem(type: .duration, value: durationMinutes, label: "minutes"))
        }

        if data.totalSteps > 0 {
            items.append(StatItem(type: .steps, value: data.totalSteps, label: "steps"))
        }

        if data.totalFloors > 0 {
            items.append(StatItem(type: .floors, value: data.totalFloors, label: "floors"))
        }

        let climbInt = Int(data.totalVerticalClimb)
        if climbInt > 0 {
            items.append(StatItem(type: .verticalClimb, value: climbInt, label: data.verticalClimbUnit))
        }

        return items.sorted { $0.type.rawValue < $1.type.rawValue }
    }

    /// Current display value for a stat, based on animation progress
    func currentValue(for stat: StatItem) -> Int {
        let progress = statProgress[stat.type] ?? 1.0
        return Int(Double(stat.value) * progress)
    }

    // MARK: - Animation

    func startAnimations() {
        animationTask = Task { await runAnimationSequence() }
    }

    func cancelAnimations() {
        animationTask?.cancel()
    }

    private func runAnimationSequence() async {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        // T+0.0s: Title fades in
        withAnimation(.easeIn(duration: reduceMotion ? 0.1 : 0.4)) {
            titleOpacity = 1.0
        }

        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 500))

        let haptics = HapticsManager.shared

        // Stats appear first
        let stats = visibleStats
        phase = .countingStats

        for (index, stat) in stats.enumerated() {
            guard !Task.isCancelled else { return }

            // Fade in the tile
            withAnimation(.easeIn(duration: reduceMotion ? 0.1 : 0.3)) {
                statOpacities[stat.type] = 1.0
            }

            if reduceMotion {
                // Skip count-up — show final values immediately
                statProgress[stat.type] = 1.0
            } else {
                // Count up from 0 → final over 0.8s
                await animateCountUp(for: stat, duration: 0.8, haptics: haptics)
            }

            // Distinct landing haptic when each stat settles.
            // Make the final stat landing heavier + trigger a quick visual impact pulse.
            if index == stats.count - 1 {
                await triggerFinalStatImpact(haptics: haptics, reduceMotion: reduceMotion)
            } else {
                haptics.trigger(.lightImpact)
            }

            // Stagger delay between stats
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        guard !Task.isCancelled else { return }

        // T+2.0s: All stats settled — celebration burst
        phase = .settled
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 180))

        // Reveal goal impact section after stats complete.
        withAnimation(.easeIn(duration: reduceMotion ? 0.1 : 0.25)) {
            showGoalSection = true
            goalSectionOpacity = 1.0
        }

        if let goalSnapshot {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 140))

            if reduceMotion {
                goalBarProgress = goalSnapshot.newPercent
            } else {
                await animateGoalBar(
                    from: goalSnapshot.previousPercent,
                    to: goalSnapshot.newPercent,
                    duration: 1.2,
                    haptics: haptics
                )
            }

            if goalSnapshot.goalCompleted {
                await runGoalCompletionTakeover(haptics: haptics, reduceMotion: reduceMotion)
            } else {
                haptics.trigger(.mediumImpact)
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 120))
                await haptics.celebrationBurst()
            }
        } else {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 120))
            await haptics.celebrationBurst()
        }

        // T+2.2s: Button fades in
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: reduceMotion ? 0.1 : 0.3)) {
            buttonOpacity = 1.0
        }
    }

    private func runGoalCompletionTakeover(
        haptics: HapticsManager,
        reduceMotion: Bool
    ) async {
        guard !Task.isCancelled else { return }

        TelemetryManager.shared.log(.celebrationGoalCompleted)

        withAnimation(.easeIn(duration: reduceMotion ? 0.1 : 0.18)) {
            showGoalCompletionScreen = true
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 40 : 100))
        haptics.trigger(.heavyImpact)

        if reduceMotion {
            haptics.trigger(.success)
            return
        }

        try? await Task.sleep(for: .milliseconds(100))
        await haptics.goalCompletionBurst()
    }

    private func triggerFinalStatImpact(haptics: HapticsManager, reduceMotion: Bool) async {
        if reduceMotion {
            await haptics.finalStatImpactBurst()
            return
        }

        let impactTask = Task { await haptics.finalStatImpactBurst() }

        withAnimation(.easeOut(duration: 0.08)) {
            statGridScale = 0.97
            heroScale = 0.95
        }

        try? await Task.sleep(for: .milliseconds(70))

        withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
            statGridScale = 1.03
            heroScale = 1.04
        }

        await impactTask.value

        try? await Task.sleep(for: .milliseconds(130))

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            statGridScale = 1.0
            heroScale = 1.0
        }
    }

    private func animateCountUp(for stat: StatItem, duration: Double, haptics: HapticsManager) async {
        let targetValue = max(stat.value, 1)
        let maxTickCount = 42
        let stepValue = max(1, Int(ceil(Double(targetValue) / Double(maxTickCount))))
        let tickCount = Int(ceil(Double(targetValue) / Double(stepValue)))
        let intervalMs = max(14, Int((duration / Double(max(tickCount, 1))) * 1000))

        var current = 0
        for i in 0..<tickCount {
            guard !Task.isCancelled else { return }
            current = min(targetValue, current + stepValue)
            statProgress[stat.type] = Double(current) / Double(targetValue)

            // Tick on every visible number increase during count-up
            // Use light impact for a more pronounced counting feel.
            haptics.trigger(.lightImpact)

            if i < tickCount - 1 {
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
        }

        // Ensure we land exactly at 1.0
        statProgress[stat.type] = 1.0
    }

    private func animateGoalBar(from start: Double, to end: Double, duration: Double, haptics: HapticsManager) async {
        goalBarProgress = start

        withAnimation(.easeInOut(duration: duration)) {
            goalBarProgress = end
        }

        let tickTask = Task {
            await emitGoalBarTicks(from: start, to: end, duration: duration, haptics: haptics)
        }

        try? await Task.sleep(for: .milliseconds(Int((duration * 1000).rounded())))
        await tickTask.value
    }

    private func emitGoalBarTicks(from start: Double, to end: Double, duration: Double, haptics: HapticsManager) async {
        let delta = abs(end - start)
        guard delta > 0.001 else { return }

        // Roughly one tick per 10% moved, capped to avoid haptic spam.
        let tickCount = min(8, max(1, Int(ceil(delta * 10))))
        let intervalMs = max(70, Int((duration / Double(tickCount)) * 1000))

        for index in 0..<tickCount {
            guard !Task.isCancelled else { return }
            haptics.trigger(.lightImpact)

            if index < tickCount - 1 {
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
        }
    }
}
