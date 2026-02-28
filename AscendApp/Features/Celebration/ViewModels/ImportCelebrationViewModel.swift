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
    var impactFlashOpacity: Double = 0
    var showGoalSection = false
    var goalSectionOpacity: Double = 0
    var goalBarProgress: Double = 0
    var shockwavePrimaryScale: CGFloat = 0.5
    var shockwavePrimaryOpacity: Double = 0
    var shockwaveSecondaryScale: CGFloat = 0.7
    var shockwaveSecondaryOpacity: Double = 0
    var lightningProgress: CGFloat = 0
    var lightningOpacity: Double = 0
    var perimeterSurgeHead: CGFloat = 0
    var perimeterSurgeTail: CGFloat = 0
    var perimeterSurgeOpacity: Double = 0

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
        let sounds = CelebrationSoundManager.shared

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
                await animateCountUp(for: stat, duration: 0.8, haptics: haptics, sounds: sounds)
            }

            // Distinct landing haptic when each stat settles.
            // Make the final stat landing heavier + trigger a quick visual impact pulse.
            if index == stats.count - 1 {
                await triggerFinalStatImpact(haptics: haptics, sounds: sounds, reduceMotion: reduceMotion)
            } else {
                haptics.trigger(.lightImpact)
                sounds.playStatLand()
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

            haptics.trigger(.mediumImpact)
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 120))
        await haptics.celebrationBurst()
        sounds.playCelebrationCompletion()

        // T+2.2s: Button fades in
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: reduceMotion ? 0.1 : 0.3)) {
            buttonOpacity = 1.0
        }
    }

    private func triggerFinalStatImpact(haptics: HapticsManager, sounds: CelebrationSoundManager, reduceMotion: Bool) async {
        if reduceMotion {
            await haptics.finalStatImpactBurst()
            sounds.playElectricExplosion()
            return
        }

        shockwavePrimaryScale = 0.7
        shockwavePrimaryOpacity = 0
        shockwaveSecondaryScale = 0.45
        shockwaveSecondaryOpacity = 0
        lightningProgress = 0
        lightningOpacity = 0
        perimeterSurgeHead = 0
        perimeterSurgeTail = 0
        perimeterSurgeOpacity = 0

        // 1) Trace the full perimeter from top-center clockwise.
        let traceDuration = 0.82
        let traceSegmentLength: CGFloat = 0.13
        perimeterSurgeOpacity = 0.98
        perimeterSurgeHead = traceSegmentLength
        perimeterSurgeTail = 0

        withAnimation(.linear(duration: traceDuration)) {
            perimeterSurgeHead = 1.0
            perimeterSurgeTail = 1.0 - traceSegmentLength
        }

        await animatePerimeterSweepHaptics(duration: traceDuration, haptics: haptics, sounds: sounds)

        // 2) Collapse/fade the trace back into top-center before strike.
        let collapseDuration = 0.20
        withAnimation(.easeOut(duration: collapseDuration)) {
            perimeterSurgeTail = 1.0
            perimeterSurgeOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(Int((collapseDuration * 1000).rounded())))

        // 3) Strike from top-center into the badge.
        lightningProgress = 0
        lightningOpacity = 1
        haptics.trigger(.mediumImpact)
        sounds.playLightningStrike()
        let lightningDuration = 0.12
        withAnimation(.linear(duration: lightningDuration)) {
            lightningProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(Int((lightningDuration * 1000).rounded())))

        // 4) Strike impact + electric explosion happen together, no delay.
        let impactTask = Task { await haptics.finalStatImpactBurst() }
        sounds.playElectricExplosion()
        withAnimation(.easeOut(duration: 0.05)) {
            lightningOpacity = 0
            statGridScale = 0.94
            heroScale = 0.90
            impactFlashOpacity = 0.36
            shockwavePrimaryOpacity = 1.0
            shockwaveSecondaryOpacity = 0.95
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.52)) {
            statGridScale = 1.06
            heroScale = 1.10
            impactFlashOpacity = 0.14
        }

        withAnimation(.easeOut(duration: 0.42)) {
            shockwavePrimaryScale = 3.2
            shockwavePrimaryOpacity = 0
            shockwaveSecondaryScale = 2.5
            shockwaveSecondaryOpacity = 0
        }

        await impactTask.value

        try? await Task.sleep(for: .milliseconds(220))

        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
            statGridScale = 1.0
            heroScale = 1.0
        }

        withAnimation(.easeOut(duration: 0.22)) {
            impactFlashOpacity = 0.0
        }
    }

    private func animatePerimeterSweepHaptics(duration: Double, haptics: HapticsManager, sounds: CelebrationSoundManager) async {
        let pulseCount = 18
        let intervalMs = max(20, Int((duration / Double(pulseCount)) * 1000))

        for index in 0..<pulseCount {
            guard !Task.isCancelled else { return }
            let progress = Double(index) / Double(max(pulseCount - 1, 1))
            haptics.triggerTraceSweep(progress: progress)
            sounds.playTracePulse(progress: progress)

            if index < pulseCount - 1 {
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
        }
    }

    private func animateCountUp(for stat: StatItem, duration: Double, haptics: HapticsManager, sounds: CelebrationSoundManager) async {
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
            if i.isMultiple(of: 2) {
                sounds.playCountTick()
            }

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
