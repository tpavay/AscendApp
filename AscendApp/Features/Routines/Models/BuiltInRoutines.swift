import Foundation

/// Pre-made routine templates that ship with the app
enum BuiltInRoutines {

    /// Returns all built-in templates (creates new instances each call)
    static var templates: [Routine] {
        [
            beginner20Min,
            hiitIntervals,
            enduranceBuilder,
            quickBurn10
        ]
    }

    /// Beginner 20min - A gentle introduction with gradual intensity increases
    /// 3 min warmup (L5) → 5 min moderate (L8) → 5 min push (L10) → 5 min moderate (L8) → 2 min cooldown (L5)
    static var beginner20Min: Routine {
        let intervals: [RoutineInterval] = [
            RoutineInterval(duration: 180, intensityValue: 5, order: 0),
            RoutineInterval(duration: 300, intensityValue: 8, order: 1),
            RoutineInterval(duration: 300, intensityValue: 10, order: 2),
            RoutineInterval(duration: 300, intensityValue: 8, order: 3),
            RoutineInterval(duration: 120, intensityValue: 5, order: 4),
        ]
        return Routine(
            name: "Beginner 20min",
            routineDescription: "A gentle introduction to stair climbing with gradual intensity increases.",
            source: .builtin,
            intervals: intervals,
            templateId: "beginner_20min",
            difficulty: 1,
            estimatedCalories: 150
        )
    }

    /// HIIT Intervals - High-intensity interval training with 30-second bursts
    /// 2 min warmup (L6) → 8x [30s hard (L15) + 30s recovery (L6)] → 2 min cooldown (L5)
    static var hiitIntervals: Routine {
        var intervals: [RoutineInterval] = [
            RoutineInterval(duration: 120, intensityValue: 6, order: 0),
        ]

        // 8 rounds of 30s hard / 30s easy
        for i in 0..<8 {
            intervals.append(RoutineInterval(duration: 30, intensityValue: 15, order: 1 + i * 2))
            intervals.append(RoutineInterval(duration: 30, intensityValue: 6, order: 2 + i * 2))
        }

        intervals.append(RoutineInterval(duration: 120, intensityValue: 5, order: 17))

        return Routine(
            name: "HIIT Intervals",
            routineDescription: "High-intensity interval training with 30-second bursts.",
            source: .builtin,
            intervals: intervals,
            templateId: "hiit_intervals",
            difficulty: 4,
            estimatedCalories: 200
        )
    }

    /// Endurance Builder - Build stamina with sustained moderate-to-hard climbing
    /// 5 min warmup (L6) → 15 min steady (L10) → 10 min push (L12) → 5 min cooldown (L6)
    static var enduranceBuilder: Routine {
        let intervals: [RoutineInterval] = [
            RoutineInterval(duration: 300, intensityValue: 6, order: 0),
            RoutineInterval(duration: 900, intensityValue: 10, order: 1),
            RoutineInterval(duration: 600, intensityValue: 12, order: 2),
            RoutineInterval(duration: 300, intensityValue: 6, order: 3),
        ]
        return Routine(
            name: "Endurance Builder",
            routineDescription: "Build stamina with sustained moderate-to-hard climbing.",
            source: .builtin,
            intervals: intervals,
            templateId: "endurance_builder",
            difficulty: 3,
            estimatedCalories: 350
        )
    }

    /// Quick Burn 10 - A fast-paced 10-minute routine for short sessions
    /// 1 min warmup (L6) → 2 min hard (L12) → 1 min recovery (L8) → 2 min harder (L14) → 1 min recovery (L8) → 2 min peak (L16) → 1 min cooldown (L5)
    static var quickBurn10: Routine {
        let intervals: [RoutineInterval] = [
            RoutineInterval(duration: 60, intensityValue: 6, order: 0),
            RoutineInterval(duration: 120, intensityValue: 12, order: 1),
            RoutineInterval(duration: 60, intensityValue: 8, order: 2),
            RoutineInterval(duration: 120, intensityValue: 14, order: 3),
            RoutineInterval(duration: 60, intensityValue: 8, order: 4),
            RoutineInterval(duration: 120, intensityValue: 16, order: 5),
            RoutineInterval(duration: 60, intensityValue: 5, order: 6),
        ]
        return Routine(
            name: "Quick Burn 10",
            routineDescription: "A fast-paced 10-minute routine for when you're short on time.",
            source: .builtin,
            intervals: intervals,
            templateId: "quick_burn_10",
            difficulty: 3,
            estimatedCalories: 120
        )
    }
}
