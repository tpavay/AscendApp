import Foundation

protocol ModerationRepositoryProtocol: Sendable {
    func fetchBlockedClimbers(
        blockerUserId: String,
        source: BlockListReadSource
    ) async throws -> [BlockedClimber]
    func block(blockerUserId: String, blockedUserId: String) async throws
    func unblock(blockerUserId: String, blockedUserId: String) async throws
    func submitReport(
        reporterUserId: String,
        reportedUserId: String,
        reason: ModerationReportReason,
        source: ModerationSource
    ) async throws
}
