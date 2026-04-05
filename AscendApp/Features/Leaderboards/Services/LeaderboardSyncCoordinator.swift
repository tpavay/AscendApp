import Foundation

actor LeaderboardSyncCoordinator {
    static let shared = LeaderboardSyncCoordinator()

    struct Request: Equatable, Sendable {
        let userId: String
        let displayName: String
        let photoURL: URL?
    }

    private var latestRequest: Request?
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Error>?
    private var syncLoopRequested = false

    private init() {}

    func enqueueSync(
        userId: String,
        displayName: String,
        photoURL: URL?,
        debounceSeconds: Double = 1.0
    ) {
        let request = Request(userId: userId, displayName: displayName, photoURL: photoURL)
        latestRequest = request
        debounceTask?.cancel()

        if syncTask != nil {
            syncLoopRequested = true
            return
        }

        debounceTask = Task { [request] in
            do {
                try await Task.sleep(for: .seconds(debounceSeconds))
            } catch {
                return
            }

            try? await self.startSyncLoop(with: request, rethrowErrors: false)
        }
    }

    func flushNow(userId: String, displayName: String, photoURL: URL?) async throws {
        let request = Request(userId: userId, displayName: displayName, photoURL: photoURL)
        latestRequest = request
        debounceTask?.cancel()
        debounceTask = nil
        try await startSyncLoop(with: request, rethrowErrors: true)
    }

    private func startSyncLoop(with request: Request, rethrowErrors: Bool) async throws {
        latestRequest = request

        if let existingTask = syncTask {
            syncLoopRequested = true
            _ = await existingTask.result
            if rethrowErrors, let latestRequest {
                try await startSyncLoop(with: latestRequest, rethrowErrors: true)
            }
            return
        }

        let task = Task { [request] in
            try await self.performSyncLoop(startingWith: request)
        }
        syncTask = task

        defer {
            syncTask = nil
        }

        let result = await task.result
        switch result {
        case .success:
            return
        case .failure(let error):
            if rethrowErrors {
                throw error
            }
        }
    }

    private func performSyncLoop(startingWith request: Request) async throws {
        var currentRequest: Request? = request

        while let request = currentRequest ?? latestRequest {
            latestRequest = nil
            currentRequest = nil

            let payloads = try await prepareSyncPayloads(for: request)

            if payloads.isEmpty {
                if syncLoopRequested {
                    syncLoopRequested = false
                    currentRequest = latestRequest
                    continue
                }
                return
            }

            var successfulPayloads: [LeaderboardSyncPayload] = []
            do {
                for payload in payloads {
                    try await withLeaderboardTimeout(seconds: 8) {
                        try await LeaderboardService.shared.syncPayload(payload)
                    }
                    successfulPayloads.append(payload)
                }
            } catch {
                if !successfulPayloads.isEmpty {
                    try await MainActor.run {
                        try LeaderboardService.shared.markSynced(payloads: successfulPayloads)
                    }
                }
                throw error
            }

            try await MainActor.run {
                try LeaderboardService.shared.markSynced(payloads: successfulPayloads)
            }
            await LeaderboardSessionCache.shared.invalidateAll()

            if syncLoopRequested {
                syncLoopRequested = false
                currentRequest = latestRequest
            }
        }
    }

    private func prepareSyncPayloads(for request: Request) async throws -> [LeaderboardSyncPayload] {
        try await MainActor.run {
            try LeaderboardService.shared.prepareSyncPayloads(
                userId: request.userId,
                displayName: request.displayName,
                photoURL: request.photoURL
            )
        }
    }
}
