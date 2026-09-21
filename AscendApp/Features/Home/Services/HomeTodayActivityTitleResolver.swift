import Foundation
import SwiftData

/// Names the climbs and routines the today rows point at, from content the app
/// already holds: the climb catalog and the routine templates. Bounded on purpose -
/// one catalog lookup per climb id and one filtered routine fetch per feed - so it
/// never grows with the climber's history.
@MainActor
struct HomeTodayActivityTitleResolver {
    let climbService: ClimbService

    init(climbService: ClimbService = .shared) {
        self.climbService = climbService
    }

    func climbName(for climbId: String?) -> String? {
        guard let climbId else { return nil }
        return (try? climbService.climb(for: climbId))?.name
    }

    /// The catalog climb a `climbDetail` destination opens, or nil when the catalog no
    /// longer carries it or it is not open yet.
    func openableClimb(for climbId: String) -> Climb? {
        guard let climb = try? climbService.climb(for: climbId), climb.isAvailable else { return nil }
        return climb
    }

    /// Template names for the ids the rows carry. Shipped templates answer without
    /// the store; a template that only exists remotely is looked up by id.
    func routineTemplateNames(
        for templateIds: Set<String>,
        modelContext: ModelContext
    ) -> [String: String] {
        var names: [String: String] = [:]
        var unresolved: [String?] = []
        for templateId in templateIds {
            if let definition = BuiltInRoutines.definitions.first(where: { $0.id == templateId }) {
                names[templateId] = definition.name
            } else {
                unresolved.append(templateId)
            }
        }
        guard !unresolved.isEmpty else { return names }

        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { unresolved.contains($0.templateId) }
        )
        for routine in (try? modelContext.fetch(descriptor)) ?? [] {
            if let templateId = routine.templateId {
                names[templateId] = routine.name
            }
        }
        return names
    }

    /// The presentation of every row, keyed by row id.
    func presentations(
        for rows: [ModeratedHomeTodayActivityRow],
        modelContext: ModelContext,
        now: Date = Date()
    ) -> [String: HomeTodayActivityRowPresentation] {
        let templateIds = Set(rows.compactMap(\.routineTemplateId))
        let templateNames = routineTemplateNames(for: templateIds, modelContext: modelContext)
        var presentations: [String: HomeTodayActivityRowPresentation] = [:]
        for row in rows {
            presentations[row.id] = HomeTodayActivityRowPresentation(
                row: row,
                climbName: climbName(for: row.climbId),
                routineTemplateName: row.routineTemplateId.flatMap { templateNames[$0] },
                now: now
            )
        }
        return presentations
    }
}
