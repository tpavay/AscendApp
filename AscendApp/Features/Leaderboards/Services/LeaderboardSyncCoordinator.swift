import Foundation

actor LeaderboardSyncCoordinator {
    static let shared = LeaderboardSyncCoordinator()

    struct Request: Equatable, Sendable {
        let userId: String
    }

    private let featureFlags: RemoteFeatureFlagStore
    private var latestRequest: Request?
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Error>?
    private var syncLoopRequested = false

    init(featureFlags: RemoteFeatureFlagStore = .shared) {
        self.featureFlags = featureFlags
    }

    func enqueueSync(
        userId: String,
        debounceSeconds: Double = 1.0
    ) {
        let request = Request(userId: userId)
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

    func flushNow(userId: String) async throws {
        let request = Request(userId: userId)
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
            // Killed: `markSynced` is never reached, so the local `LeaderboardStats` stay dirty and
            // the next enqueue after the flag returns republishes them. Re-read per iteration so a
            // switch thrown during a burst of saves halts at the next request instead of after the
            // loop drains. Gated here rather than at `enqueueSync` so `flushNow` is covered too.
            guard RemoteFeatureGate.allows(
                .leaderboardPublishing,
                path: "LeaderboardSyncCoordinator.performSyncLoop",
                store: featureFlags
            ) else {
                latestRequest = nil
                syncLoopRequested = false
                return
            }

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
        let profile = try? await UserDataRepository.shared.getUserFromFirestore(userId: request.userId)
        let leaderboardProfile = profile.map {
            LeaderboardProfileSnapshot(userId: request.userId, userData: $0)
        }

        return try await MainActor.run {
            try LeaderboardService.shared.prepareSyncPayloads(
                userId: request.userId,
                profile: leaderboardProfile
            )
        }
    }
}
