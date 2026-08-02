import Foundation

/// The cloud backup for routines the climber authored, and the folders they
/// organise them into.
///
/// Distinct from `RoutineTemplateRepository`, which reads server-owned
/// published catalog content and can never be written to.
protocol UserRoutineRemoteRepositoryProtocol: Sendable {
    func fetchRoutines(userId: String) async throws -> [RemoteUserRoutineRecord]
    func fetchFolders(userId: String) async throws -> [RemoteRoutineFolderRecord]

    func upsertRoutine(
        userId: String,
        routineId: UUID,
        document: FirestoreUserRoutineDocument
    ) async throws

    func upsertFolder(
        userId: String,
        folderId: UUID,
        document: FirestoreRoutineFolderDocument
    ) async throws

    func deleteRoutine(userId: String, routineId: UUID) async throws
    func deleteFolder(userId: String, folderId: UUID) async throws
}
