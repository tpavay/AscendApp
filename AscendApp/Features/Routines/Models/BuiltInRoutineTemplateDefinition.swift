import Foundation

struct BuiltInRoutineTemplateDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let routineDescription: String
    let intervals: [RelativeRoutineInterval]
    let browseSections: [BuiltInRoutineBrowseSection]
    let isFeatured: Bool
    let difficulty: Int?
    let estimatedCalories: Int?
}
