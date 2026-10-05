import Foundation
@preconcurrency import FirebaseFirestore

// The only place the app passes `source: .server`. Every forced read goes through
// `ServerPreferredRead`, which owns the quiet retry; `scripts/test/server-read-contract.test.mjs`
// fails when a call site forces the server on its own.

extension Query {
    /// The server's documents, never the cache's, with `ServerPreferredRead`'s one quiet retry.
    func getServerDocuments(
        isolation: isolated (any Actor)? = #isolation,
        quietRetry: Bool = true
    ) async throws -> QuerySnapshot {
        try await ServerPreferredRead.serverRequired(isolation: isolation, quietRetry: quietRetry) {
            try await self.getDocuments(source: .server)
        }
    }
}

extension DocumentReference {
    /// The server's document, never the cache's, with `ServerPreferredRead`'s one quiet retry.
    func getServerDocument(
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> DocumentSnapshot {
        try await ServerPreferredRead.serverRequired(isolation: isolation) {
            try await self.getDocument(source: .server)
        }
    }
}

extension AggregateQuery {
    /// The server's aggregation, with `ServerPreferredRead`'s one quiet retry. An aggregation has
    /// no cached form, so there is nothing to fall back to.
    func getServerAggregation(
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> AggregateQuerySnapshot {
        try await ServerPreferredRead.serverRequired(isolation: isolation) {
            try await self.getAggregation(source: .server)
        }
    }
}
