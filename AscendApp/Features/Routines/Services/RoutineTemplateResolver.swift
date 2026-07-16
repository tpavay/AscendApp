import Foundation

enum RoutineTemplateResolver {
    static func resolveLevel(for zone: ClimbZone, baseLevel: Int) -> Int {
        SPMMappingService.clampedLevel(baseLevel + zone.levelOffset)
    }

    static func resolveIntervals(
        _ intervals: [RelativeRoutineInterval],
        baseLevel: Int
    ) -> [RoutineInterval] {
        intervals.enumerated().map { index, interval in
            RoutineInterval(
                duration: interval.duration,
                intensityType: .level,
                intensityValue: resolveLevel(for: interval.zone, baseLevel: baseLevel),
                modifiers: interval.modifiers,
                order: index
            )
        }
    }

    static func resolveTemplate(
        _ template: BuiltInRoutineTemplateDefinition,
        baseLevel: Int,
        displayOrder: Int = 0
    ) -> Routine {
        Routine(
            name: template.name,
            routineDescription: template.routineDescription,
            source: .builtin,
            intervals: resolveIntervals(template.intervals, baseLevel: baseLevel),
            templateId: template.id,
            difficulty: template.difficulty,
            estimatedCalories: template.estimatedCalories,
            browseSections: template.browseSections,
            isFeaturedTemplate: template.isFeatured,
            templateDisplayOrder: displayOrder,
            templateFeaturedOrder: template.isFeatured ? displayOrder : nil
        )
    }
}
