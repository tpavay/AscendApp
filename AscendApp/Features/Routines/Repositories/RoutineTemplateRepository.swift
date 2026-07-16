import Foundation

protocol RoutineTemplateRepository: Sendable {
    func fetchPublishedTemplates() async throws -> [RemoteRoutineTemplate]
}
