import Foundation

struct RemoteRoutineTemplate: Identifiable, Sendable {
    let id: String
    let version: Int?
    let name: String
    let routineDescription: String
    let intervals: [RemoteRoutineTemplateInterval]
    let browseSections: [BuiltInRoutineBrowseSection]
    let isFeatured: Bool
    let displayOrder: Int
    let featuredOrder: Int?
    let difficulty: Int?
    let estimatedCalories: Int?
    let updatedAt: Date?

    func resolvedRoutine(baseLevel: Int) -> Routine {
        Routine(
            name: name,
            routineDescription: routineDescription,
            source: .remoteTemplate,
            intervals: intervals.enumerated().map { index, interval in
                interval.resolvedInterval(baseLevel: baseLevel, order: index)
            },
            templateId: id,
            templateVersion: version,
            difficulty: difficulty,
            estimatedCalories: estimatedCalories,
            browseSections: browseSections,
            isFeaturedTemplate: isFeatured,
            templateDisplayOrder: displayOrder,
            templateFeaturedOrder: featuredOrder
        )
    }
}

struct RemoteRoutineTemplateInterval: Sendable {
    enum Intensity: Sendable {
        case level(Int)
        case stepsPerMinute(Int)
        case zone(ClimbZone)
    }

    let duration: TimeInterval
    let intensity: Intensity
    let modifiers: IntervalModifiers

    func resolvedInterval(baseLevel: Int, order: Int) -> RoutineInterval {
        switch intensity {
        case .level(let level):
            return RoutineInterval(
                duration: duration,
                intensityType: .level,
                intensityValue: SPMMappingService.clampedLevel(level),
                modifiers: modifiers,
                order: order
            )
        case .stepsPerMinute(let spm):
            return RoutineInterval(
                duration: duration,
                intensityType: .stepsPerMinute,
                intensityValue: max(spm, 1),
                modifiers: modifiers,
                order: order
            )
        case .zone(let zone):
            return RoutineInterval(
                duration: duration,
                intensityType: .level,
                intensityValue: RoutineTemplateResolver.resolveLevel(for: zone, baseLevel: baseLevel),
                modifiers: modifiers,
                order: order
            )
        }
    }
}
