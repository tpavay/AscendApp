import Foundation

/// The built-in routine the Climb sheet names as today's pick.
///
/// Rolls over at the same hour as the daily climb, so "Today" means the same stretch of the
/// clock on both rows. Pure: the sheet reads the answer, it never decides it.
enum DailyRoutineRecommendationPolicy {
    struct Pick: Equatable, Sendable {
        let templateId: String
        let name: String
        let durationMinutes: Int
    }

    static func recommendation(
        from definitions: [BuiltInRoutineTemplateDefinition] = BuiltInRoutines.definitions,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Pick? {
        let featured = definitions.filter(\.isFeatured).sorted { $0.id < $1.id }
        guard !featured.isEmpty else { return nil }

        let effectiveDate = calendar.date(
            byAdding: .hour,
            value: -DailyClimbRecommendationPolicy.rolloverHour,
            to: date
        ) ?? date
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: effectiveDate) ?? 0
        let definition = featured[dayOrdinal % featured.count]
        let seconds = definition.intervals.reduce(0) { $0 + $1.duration }

        return Pick(
            templateId: definition.id,
            name: definition.name,
            durationMinutes: max(Int((seconds / 60).rounded()), 1)
        )
    }
}
