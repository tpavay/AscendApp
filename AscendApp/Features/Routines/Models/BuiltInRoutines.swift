import Foundation

/// Pre-made routine templates that ship with the app
enum BuiltInRoutines {
    static var templateIdsInDisplayOrder: [String] {
        definitions.map(\.id)
    }

    static var featuredTemplateIdsInDisplayOrder: [String] {
        definitions.filter(\.isFeatured).map(\.id)
    }

    static func templateIds(in section: BuiltInRoutineBrowseSection) -> [String] {
        definitions
            .filter { $0.browseSections.contains(section) }
            .map(\.id)
    }

    static var definitions: [BuiltInRoutineTemplateDefinition] {
        [
            BuiltInRoutineTemplateDefinition(
                id: "first_climb_10",
                name: "First Climb 10",
                routineDescription: "Settle into a short, steady climb with time to warm up and ease back down. Pick this when you want the simplest possible starting point.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 120),
                    RelativeRoutineInterval(zone: .steady, duration: 360),
                    RelativeRoutineInterval(zone: .recovery, duration: 120)
                ],
                browseSections: [.gettingStarted],
                isFeatured: false,
                difficulty: 1,
                estimatedCalories: 85
            ),
            BuiltInRoutineTemplateDefinition(
                id: "first_climb_15",
                name: "First Climb 15",
                routineDescription: "Build a little more time at your steady pace without adding complexity. Pick this when you're ready to stay on the machine longer and build confidence.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 120),
                    RelativeRoutineInterval(zone: .steady, duration: 600),
                    RelativeRoutineInterval(zone: .recovery, duration: 180)
                ],
                browseSections: [.gettingStarted],
                isFeatured: false,
                difficulty: 1,
                estimatedCalories: 125
            ),
            BuiltInRoutineTemplateDefinition(
                id: "gentle_build",
                name: "Gentle Build",
                routineDescription: "Start easy, move into a steady working pace, then back off before the finish. Pick this when you want a smooth introduction to changing intensity.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 120),
                    RelativeRoutineInterval(zone: .easy, duration: 180),
                    RelativeRoutineInterval(zone: .steady, duration: 180),
                    RelativeRoutineInterval(zone: .easy, duration: 120),
                    RelativeRoutineInterval(zone: .recovery, duration: 120)
                ],
                browseSections: [.gettingStarted],
                isFeatured: false,
                difficulty: 1,
                estimatedCalories: 100
            ),
            BuiltInRoutineTemplateDefinition(
                id: "first_intervals",
                name: "First Intervals",
                routineDescription: "Alternate short steady pushes with easy recoveries to break the workout into manageable chunks. Pick this when you want variety without jumping into hard HIIT.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 120),
                    RelativeRoutineInterval(zone: .steady, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 60),
                    RelativeRoutineInterval(zone: .steady, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 60),
                    RelativeRoutineInterval(zone: .steady, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 60),
                    RelativeRoutineInterval(zone: .steady, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 60),
                    RelativeRoutineInterval(zone: .recovery, duration: 120)
                ],
                browseSections: [.gettingStarted],
                isFeatured: false,
                difficulty: 2,
                estimatedCalories: 105
            ),
            BuiltInRoutineTemplateDefinition(
                id: "challenge_10_8_4",
                name: "Quick Climb",
                routineDescription: "A short climb with a 1-minute warmup, 8-minute steady push, and 1-minute recovery. Pick this when you want a fast, balanced effort.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .steady, duration: 480),
                    RelativeRoutineInterval(zone: .recovery, duration: 60)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 1,
                estimatedCalories: 90
            ),
            BuiltInRoutineTemplateDefinition(
                id: "challenge_25_7_2",
                name: "Steady State",
                routineDescription: "Ease in for 5 minutes, then hold your steady pace for 25 minutes. Pick this when you want sustained work without big intensity changes.",
                intervals: [
                    RelativeRoutineInterval(zone: .easy, duration: 300),
                    RelativeRoutineInterval(zone: .steady, duration: 1_500)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 2,
                estimatedCalories: 260
            ),
            BuiltInRoutineTemplateDefinition(
                id: "stair_3030",
                name: "Tempo Switch",
                routineDescription: "Alternate easy recoveries with longer tempo pushes across 30 minutes. Pick this when you want rhythm changes without going full HIIT.",
                intervals: [
                    RelativeRoutineInterval(zone: .easy, duration: 120),
                    RelativeRoutineInterval(zone: .tempo, duration: 300),
                    RelativeRoutineInterval(zone: .easy, duration: 120),
                    RelativeRoutineInterval(zone: .tempo, duration: 360),
                    RelativeRoutineInterval(zone: .easy, duration: 120),
                    RelativeRoutineInterval(zone: .tempo, duration: 300),
                    RelativeRoutineInterval(zone: .easy, duration: 480)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 3,
                estimatedCalories: 280
            ),
            BuiltInRoutineTemplateDefinition(
                id: "double_step_intervals",
                name: "Skip Step Intervals",
                routineDescription: "Alternate reset intervals with skip-step climbing to raise the demand. Pick this when you want variety and more lower-body challenge.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 90, modifiers: .skipStep),
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .steady, duration: 90, modifiers: .skipStep),
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .steady, duration: 90, modifiers: .skipStep),
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 90, modifiers: .skipStep),
                    RelativeRoutineInterval(zone: .recovery, duration: 60)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 3,
                estimatedCalories: 130
            ),
            BuiltInRoutineTemplateDefinition(
                id: "zone_2_steady",
                name: "Zone 2 Easy",
                routineDescription: "Stay mostly at an easy, conversational pace with a brief warmup and recovery. Pick this when you want aerobic volume without a hard finish.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .easy, duration: 2_280),
                    RelativeRoutineInterval(zone: .recovery, duration: 60)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 2,
                estimatedCalories: 320
            ),
            BuiltInRoutineTemplateDefinition(
                id: "hiit_crusher",
                name: "HIIT Sprint",
                routineDescription: "Short sprint and threshold bursts alternate with recovery throughout the session. Pick this when you want the hardest effort in the shortest time.",
                intervals: [
                    RelativeRoutineInterval(zone: .warmup, duration: 60),
                    RelativeRoutineInterval(zone: .sprint, duration: 30),
                    RelativeRoutineInterval(zone: .recovery, duration: 30),
                    RelativeRoutineInterval(zone: .sprint, duration: 30),
                    RelativeRoutineInterval(zone: .recovery, duration: 30),
                    RelativeRoutineInterval(zone: .threshold, duration: 30),
                    RelativeRoutineInterval(zone: .recovery, duration: 30),
                    RelativeRoutineInterval(zone: .sprint, duration: 30),
                    RelativeRoutineInterval(zone: .recovery, duration: 30),
                    RelativeRoutineInterval(zone: .threshold, duration: 30),
                    RelativeRoutineInterval(zone: .recovery, duration: 30),
                    RelativeRoutineInterval(zone: .warmup, duration: 60)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 5,
                estimatedCalories: 170
            ),
            BuiltInRoutineTemplateDefinition(
                id: "pyramid_climb",
                name: "Pyramid Climb",
                routineDescription: "Climb up through each zone, hit a hard peak, then step back down. Pick this when you want a progressive challenge with a clear build and release.",
                intervals: [
                    RelativeRoutineInterval(zone: .easy, duration: 120),
                    RelativeRoutineInterval(zone: .steady, duration: 120),
                    RelativeRoutineInterval(zone: .tempo, duration: 120),
                    RelativeRoutineInterval(zone: .threshold, duration: 120),
                    RelativeRoutineInterval(zone: .sprint, duration: 240),
                    RelativeRoutineInterval(zone: .threshold, duration: 120),
                    RelativeRoutineInterval(zone: .tempo, duration: 120),
                    RelativeRoutineInterval(zone: .steady, duration: 120),
                    RelativeRoutineInterval(zone: .easy, duration: 120)
                ],
                browseSections: [],
                isFeatured: true,
                difficulty: 4,
                estimatedCalories: 220
            )
        ]
    }

    static func resolvedTemplates(for baseLevel: Int) -> [Routine] {
        definitions.map { RoutineTemplateResolver.resolveTemplate($0, baseLevel: baseLevel) }
    }

    static var previewTemplates: [Routine] {
        resolvedTemplates(for: 8)
    }
}
