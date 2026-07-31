import Foundation
import Testing
@testable import AscendApp

@MainActor
struct ModerationStoreTests {
    actor RepositorySpy: ModerationRepositoryProtocol {
        struct BlockCall: Equatable {
            let blockerUserId: String
            let blockedUserId: String
        }

        struct ReportCall: Equatable {
            let reporterUserId: String
            let reportedUserId: String
            let reason: ModerationReportReason
            let source: ModerationSource
        }

        var fetchedBlocks: [BlockedClimber] = []
        /// Firestore answers an unsynced collection query with an empty
        /// snapshot, not an error, so an empty cache read succeeds here too.
        var cachedBlocks: [BlockedClimber] = []
        var cacheFails = false
        var fetchedSources: [BlockListReadSource] = []
        var fetchedUserIds: [String] = []
        var blockCalls: [BlockCall] = []
        var unblockCalls: [BlockCall] = []
        var reportCalls: [ReportCall] = []
        var blockFails = false
        var unblockFails = false
        var reportFails = false
        var fetchFails = false
        var blockSuspends = false
        var blockStarted = false
        var blockStartedContinuation: CheckedContinuation<Void, Never>?
        var blockReleaseContinuation: CheckedContinuation<Void, Never>?
        var unblockSuspends = false
        var unblockStarted = false
        var unblockStartedContinuation: CheckedContinuation<Void, Never>?
        var unblockReleaseContinuation: CheckedContinuation<Void, Never>?
        var fetchSuspends = false
        var fetchCallCount = 0
        var fetchContinuations: [
            Int: CheckedContinuation<[BlockedClimber], any Error>
        ] = [:]

        func fetchBlockedClimbers(
            blockerUserId: String,
            source: BlockListReadSource
        ) async throws -> [BlockedClimber] {
            fetchedSources.append(source)
            if source == .cache {
                if cacheFails {
                    throw TestFailure.expected
                }
                return cachedBlocks
            }

            fetchCallCount += 1
            fetchedUserIds.append(blockerUserId)
            let call = fetchCallCount
            if fetchSuspends {
                return try await withCheckedThrowingContinuation { continuation in
                    fetchContinuations[call] = continuation
                }
            }
            if fetchFails {
                throw TestFailure.expected
            }
            return fetchedBlocks
        }

        func block(blockerUserId: String, blockedUserId: String) async throws {
            blockStarted = true
            blockStartedContinuation?.resume()
            blockStartedContinuation = nil
            if blockSuspends {
                await withCheckedContinuation { continuation in
                    blockReleaseContinuation = continuation
                }
            }
            if blockFails {
                throw TestFailure.expected
            }
            blockCalls.append(
                BlockCall(
                    blockerUserId: blockerUserId,
                    blockedUserId: blockedUserId
                )
            )
        }

        func unblock(blockerUserId: String, blockedUserId: String) async throws {
            unblockStarted = true
            unblockStartedContinuation?.resume()
            unblockStartedContinuation = nil
            if unblockSuspends {
                await withCheckedContinuation { continuation in
                    unblockReleaseContinuation = continuation
                }
            }
            if unblockFails {
                throw TestFailure.expected
            }
            unblockCalls.append(
                BlockCall(
                    blockerUserId: blockerUserId,
                    blockedUserId: blockedUserId
                )
            )
        }

        func submitReport(
            reporterUserId: String,
            reportedUserId: String,
            reason: ModerationReportReason,
            source: ModerationSource
        ) async throws {
            if reportFails {
                throw TestFailure.expected
            }
            reportCalls.append(
                ReportCall(
                    reporterUserId: reporterUserId,
                    reportedUserId: reportedUserId,
                    reason: reason,
                    source: source
                )
            )
        }

        func setFetchedBlocks(_ blocks: [BlockedClimber]) {
            fetchedBlocks = blocks
        }

        func setBlockFails(_ shouldFail: Bool) {
            blockFails = shouldFail
        }

        func setUnblockFails(_ shouldFail: Bool) {
            unblockFails = shouldFail
        }

        func setReportFails(_ shouldFail: Bool) {
            reportFails = shouldFail
        }

        func setFetchFails(_ shouldFail: Bool) {
            fetchFails = shouldFail
        }

        func setCachedBlocks(_ blocks: [BlockedClimber]) {
            cachedBlocks = blocks
            cacheFails = false
        }

        func setCacheFails(_ shouldFail: Bool) {
            cacheFails = shouldFail
        }

        func suspendBlock() {
            blockSuspends = true
        }

        func suspendUnblock() {
            unblockSuspends = true
        }

        func suspendFetches() {
            fetchSuspends = true
        }

        func releaseFetch(
            _ call: Int,
            returning blocks: [BlockedClimber]
        ) {
            fetchContinuations.removeValue(forKey: call)?.resume(returning: blocks)
        }

        func hasStartedFetch(_ call: Int) -> Bool {
            fetchCallCount >= call
        }

        func waitUntilBlockStarts() async {
            guard !blockStarted else { return }
            await withCheckedContinuation { continuation in
                blockStartedContinuation = continuation
            }
        }

        func waitUntilUnblockStarts() async {
            guard !unblockStarted else { return }
            await withCheckedContinuation { continuation in
                unblockStartedContinuation = continuation
            }
        }

        func releaseBlock() {
            blockSuspends = false
            blockReleaseContinuation?.resume()
            blockReleaseContinuation = nil
        }

        func releaseUnblock() {
            unblockSuspends = false
            unblockReleaseContinuation?.resume()
            unblockReleaseContinuation = nil
        }
    }

    @MainActor
    final class ServerSyncMarkerSpy: BlockListServerSyncMarking {
        private(set) var syncedUserIds: Set<String>

        init(syncedUserIds: Set<String> = []) {
            self.syncedUserIds = syncedUserIds
        }

        func hasSyncedFromServer(userId: String) -> Bool {
            syncedUserIds.contains(userId)
        }

        func recordServerSync(userId: String) {
            syncedUserIds.insert(userId)
        }
    }

    enum TestFailure: Error {
        case expected
    }

    @Test
    func hydrationRestoresServerBlocksForANewDevice() async {
        let repository = RepositorySpy()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "blocked-user", createdAt: .now)
        ])
        let store = makeStore(repository: repository)

        await store.hydrate(for: "viewer")

        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds == ["blocked-user"])
        #expect(await repository.fetchedSources == [.server])
    }

    /// A cold launch offline defers to whatever Firestore already cached on this
    /// device instead of masking every climber on a board. A non-empty cache
    /// proves the list reached this device, so no marker is needed.
    @Test
    func firstHydrationFallsBackToTheDeviceCacheWhenTheServerFails() async {
        let repository = RepositorySpy()
        await repository.setFetchFails(true)
        await repository.setCachedBlocks([
            BlockedClimber(userId: "cached-block", createdAt: .now)
        ])
        let marker = ServerSyncMarkerSpy()
        let store = makeStore(repository: repository, serverSyncMarker: marker)

        await store.hydrate(for: "viewer")

        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds == ["cached-block"])
        #expect(store.hydrationErrorMessage == nil)
        #expect(await repository.fetchedSources == [.server, .cache])
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden == false)
        #expect(marker.syncedUserIds.isEmpty)
    }

    /// Firestore answers a never-synced collection query with an empty snapshot
    /// rather than an error, so an empty cache proves nothing on its own. Without
    /// a recorded server sync the session must stay masked.
    @Test
    func neverSyncedDeviceStaysMaskedWhenTheCacheReadsEmpty() async {
        let repository = RepositorySpy()
        await repository.setFetchFails(true)
        await repository.setCachedBlocks([])
        let marker = ServerSyncMarkerSpy()
        let store = makeStore(repository: repository, serverSyncMarker: marker)

        await store.hydrate(for: "viewer")

        #expect(store.isBlockListHydrated == false)
        #expect(store.blockedUserIds.isEmpty)
        #expect(store.hydrationErrorMessage != nil)
        #expect(await repository.fetchedSources == [.server, .cache])
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden)
        #expect(marker.syncedUserIds.isEmpty)
    }

    /// Once this account has synced here, an empty cache means what it says, so a
    /// user who has blocked nobody is not masked forever.
    @Test
    func emptyCacheHydratesOnceAServerSyncHasBeenRecorded() async {
        let repository = RepositorySpy()
        await repository.setFetchFails(true)
        await repository.setCachedBlocks([])
        let store = makeStore(
            repository: repository,
            serverSyncMarker: ServerSyncMarkerSpy(syncedUserIds: ["viewer"])
        )

        await store.hydrate(for: "viewer")

        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds.isEmpty)
        #expect(store.hydrationErrorMessage == nil)
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden == false)
    }

    /// The marker is proof of a server round trip. A cache-only hydration must not
    /// be able to certify itself for the next launch.
    @Test
    func onlyASuccessfulServerReadRecordsTheSyncMarker() async {
        let repository = RepositorySpy()
        await repository.setFetchFails(true)
        await repository.setCachedBlocks([
            BlockedClimber(userId: "cached-block", createdAt: .now)
        ])
        let marker = ServerSyncMarkerSpy()
        let store = makeStore(repository: repository, serverSyncMarker: marker)
        await store.hydrate(for: "viewer")

        #expect(marker.syncedUserIds.isEmpty)

        await repository.setFetchFails(false)
        await store.hydrate(for: "viewer")

        #expect(marker.syncedUserIds == ["viewer"])
        #expect(marker.hasSyncedFromServer(userId: "other-viewer") == false)
    }

    /// Another account signing in on this device must not inherit the marker.
    @Test
    func aSyncMarkerNeverAppliesToADifferentAccount() async {
        let repository = RepositorySpy()
        await repository.setFetchFails(true)
        await repository.setCachedBlocks([])
        let store = makeStore(
            repository: repository,
            serverSyncMarker: ServerSyncMarkerSpy(syncedUserIds: ["viewer"])
        )

        await store.hydrate(for: "other-viewer")

        #expect(store.isBlockListHydrated == false)
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden)
    }

    /// A refresh already has a list at least as fresh as the cache, so it never
    /// falls back - a thinner cache read must not drop a known block.
    @Test
    func refreshFailureNeverReplacesTheKnownListWithTheCache() async {
        let repository = RepositorySpy()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "blocked-user", createdAt: .now)
        ])
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        await repository.setFetchFails(true)
        await repository.setCachedBlocks([])
        await store.hydrate(for: "viewer")

        #expect(store.blockedUserIds == ["blocked-user"])
        #expect(await repository.fetchedSources == [.server, .server])
    }

    @Test
    func blockingImmediatelyUpdatesRenderCacheAndDoesNotReport() async throws {
        let repository = RepositorySpy()
        await repository.suspendBlock()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        let blockTask = Task {
            try await store.block(
                blockerUserId: "viewer",
                blockedUserId: "blocked-user"
            )
        }
        await repository.waitUntilBlockStarts()

        #expect(store.blockedUserIds == ["blocked-user"])
        #expect(await repository.blockCalls.isEmpty)
        #expect(await repository.reportCalls.isEmpty)

        await repository.releaseBlock()
        try await blockTask.value
        #expect(
            await repository.blockCalls == [
                .init(blockerUserId: "viewer", blockedUserId: "blocked-user")
            ]
        )
    }

    @Test
    func failedServerBlockNeverBecomesAuthoritativeLocally() async {
        let repository = RepositorySpy()
        await repository.setBlockFails(true)
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        await #expect(throws: TestFailure.self) {
            try await store.block(blockerUserId: "viewer", blockedUserId: "blocked-user")
        }

        #expect(store.blockedUserIds.isEmpty)
    }

    @Test
    func reportingDoesNotCreateABlock() async throws {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        try await store.report(
            reporterUserId: "viewer",
            reportedUserId: "reported-user",
            reason: .inappropriateName,
            source: .profile
        )

        #expect(store.blockedUserIds.isEmpty)
        #expect(await repository.blockCalls.isEmpty)
        #expect(
            await repository.reportCalls == [
                .init(
                    reporterUserId: "viewer",
                    reportedUserId: "reported-user",
                    reason: .inappropriateName,
                    source: .profile
                )
            ]
        )
    }

    @Test
    func unblockingPersistsBeforeRemovingRenderCacheEntry() async throws {
        let repository = RepositorySpy()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "blocked-user", createdAt: .now)
        ])
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        try await store.unblock(blockerUserId: "viewer", blockedUserId: "blocked-user")

        #expect(store.blockedUserIds.isEmpty)
        #expect(
            await repository.unblockCalls == [
                .init(blockerUserId: "viewer", blockedUserId: "blocked-user")
            ]
        )
    }

    @Test
    func staleSameUserHydrationCannotOverwriteANewerSession() async {
        let repository = RepositorySpy()
        await repository.suspendFetches()
        let store = makeStore(repository: repository)

        let oldHydration = Task {
            await store.hydrate(for: "viewer")
        }
        while !(await repository.hasStartedFetch(1)) {
            await Task.yield()
        }

        store.clear()
        let newHydration = Task {
            await store.hydrate(for: "viewer")
        }
        while !(await repository.hasStartedFetch(2)) {
            await Task.yield()
        }

        await repository.releaseFetch(
            2,
            returning: [
                BlockedClimber(userId: "new-session-block", createdAt: .now)
            ]
        )
        await newHydration.value

        #expect(store.isBlockListHydrated)
        #expect(store.isHydrating == false)
        #expect(store.blockedUserIds == ["new-session-block"])

        await repository.releaseFetch(
            1,
            returning: [
                BlockedClimber(userId: "stale-session-block", createdAt: .now)
            ]
        )
        await oldHydration.value

        #expect(store.isBlockListHydrated)
        #expect(store.isHydrating == false)
        #expect(store.blockedUserIds == ["new-session-block"])
    }

    @Test
    func successfulBlockThatBecomesStaleForcesAuthoritativeRehydration() async throws {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")
        await repository.suspendBlock()
        await repository.suspendFetches()

        let blockTask = Task {
            try await store.block(
                blockerUserId: "viewer",
                blockedUserId: "blocked-user"
            )
        }
        await repository.waitUntilBlockStarts()

        let foregroundHydration = Task {
            await store.hydrate(for: "viewer")
        }
        while !(await repository.hasStartedFetch(2)) {
            await Task.yield()
        }

        await repository.releaseBlock()
        while !(await repository.hasStartedFetch(3)) {
            await Task.yield()
        }
        await repository.releaseFetch(2, returning: [])
        await repository.releaseFetch(
            3,
            returning: [
                BlockedClimber(userId: "blocked-user", createdAt: .now)
            ]
        )

        await foregroundHydration.value
        try await blockTask.value
        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds == ["blocked-user"])
    }

    @Test
    func successfulUnblockThatBecomesStaleForcesAuthoritativeRehydration() async throws {
        let repository = RepositorySpy()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "blocked-user", createdAt: .now)
        ])
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")
        await repository.suspendUnblock()
        await repository.suspendFetches()

        let unblockTask = Task {
            try await store.unblock(
                blockerUserId: "viewer",
                blockedUserId: "blocked-user"
            )
        }
        await repository.waitUntilUnblockStarts()

        let foregroundHydration = Task {
            await store.hydrate(for: "viewer")
        }
        while !(await repository.hasStartedFetch(2)) {
            await Task.yield()
        }

        await repository.releaseUnblock()
        while !(await repository.hasStartedFetch(3)) {
            await Task.yield()
        }
        await repository.releaseFetch(
            2,
            returning: [
                BlockedClimber(userId: "blocked-user", createdAt: .now)
            ]
        )
        await repository.releaseFetch(3, returning: [])

        await foregroundHydration.value
        try await unblockTask.value
        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds.isEmpty)
    }

    @Test
    func staleUserAWriteNeverRehydratesOverUserB() async throws {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "user-a")
        await repository.suspendBlock()

        let blockTask = Task {
            try await store.block(
                blockerUserId: "user-a",
                blockedUserId: "blocked-user"
            )
        }
        await repository.waitUntilBlockStarts()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "user-b-block", createdAt: .now)
        ])
        await store.hydrate(for: "user-b")
        await repository.releaseBlock()
        try await blockTask.value

        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds == ["user-b-block"])
        #expect(await repository.fetchedUserIds == ["user-a", "user-b"])
    }

    @Test
    func successfulStaleWriteAfterSignOutDoesNotRestartHydration() async throws {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")
        await repository.suspendBlock()

        let blockTask = Task {
            try await store.block(
                blockerUserId: "viewer",
                blockedUserId: "blocked-user"
            )
        }
        await repository.waitUntilBlockStarts()
        store.clear()
        await repository.releaseBlock()
        try await blockTask.value

        #expect(store.isBlockListHydrated == false)
        #expect(store.blockedUserIds.isEmpty)
        #expect(await repository.fetchedUserIds == ["viewer"])
    }

    @Test
    func failedUnblockAndReportPreserveModerationState() async {
        let repository = RepositorySpy()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "blocked-user", createdAt: .now)
        ])
        await repository.setUnblockFails(true)
        await repository.setReportFails(true)
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        await #expect(throws: TestFailure.self) {
            try await store.unblock(
                blockerUserId: "viewer",
                blockedUserId: "blocked-user"
            )
        }
        await #expect(throws: TestFailure.self) {
            try await store.report(
                reporterUserId: "viewer",
                reportedUserId: "reported-user",
                reason: .spam,
                source: .profile
            )
        }

        #expect(store.blockedUserIds == ["blocked-user"])
        #expect(store.isBlockListHydrated)
    }

    /// Neither source can produce a list - the server is unreachable and local
    /// persistence itself is unavailable - so every climber stays masked.
    @Test
    func failedHydrationStaysFailClosed() async {
        let repository = RepositorySpy()
        await repository.setFetchFails(true)
        await repository.setCacheFails(true)
        let store = makeStore(repository: repository)

        await store.hydrate(for: "viewer")

        #expect(store.isBlockListHydrated == false)
        #expect(store.blockedUserIds.isEmpty)
        #expect(store.hydrationErrorMessage != nil)
        #expect(await repository.fetchedSources == [.server, .cache])
        let identity = store.moderate(
            ProfileUserIdentity(
                userId: "other-user",
                displayName: "Raw Name",
                photoURL: URL(string: "https://example.com/raw.jpg")
            ),
            isCurrentUser: false
        )
        #expect(identity.isHidden)
        #expect(identity.displayName != "Raw Name")
        #expect(identity.photoURL == nil)
    }

    /// `hydrate` runs on every foreground, not just at launch. Re-arming the
    /// fail-closed flag there re-masked every climber app-wide until the round
    /// trip finished.
    @Test
    func refreshingAnAlreadyHydratedSessionNeverReMasks() async {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")
        #expect(store.isBlockListHydrated)

        await repository.suspendFetches()
        let refresh = Task { await store.hydrate(for: "viewer") }
        while !(await repository.hasStartedFetch(2)) {
            await Task.yield()
        }

        #expect(store.isBlockListHydrated)
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden == false)

        await repository.releaseFetch(2, returning: [])
        await refresh.value
        #expect(store.isBlockListHydrated)
    }

    /// An offline refresh keeps the last known good list rather than dropping to
    /// empty or to fail-closed for the rest of the session.
    @Test
    func failedRefreshKeepsTheLastKnownGoodBlockList() async {
        let repository = RepositorySpy()
        await repository.setFetchedBlocks([
            BlockedClimber(userId: "blocked-user", createdAt: .now)
        ])
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")
        #expect(store.blockedUserIds == ["blocked-user"])

        await repository.setFetchFails(true)
        await store.hydrate(for: "viewer")

        #expect(store.isBlockListHydrated)
        #expect(store.blockedUserIds == ["blocked-user"])
        #expect(store.hydrationErrorMessage != nil)
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden == false)
    }

    /// A brand-new session still renders masked until its first hydration lands.
    @Test
    func brandNewSessionRendersMaskedUntilFirstHydrationCompletes() async {
        let repository = RepositorySpy()
        await repository.suspendFetches()
        let store = makeStore(repository: repository)

        let hydration = Task { await store.hydrate(for: "viewer") }
        while !(await repository.hasStartedFetch(1)) {
            await Task.yield()
        }

        #expect(store.isBlockListHydrated == false)
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden)

        await repository.releaseFetch(1, returning: [])
        await hydration.value
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden == false)
    }

    /// Signing in as somebody else must fail closed again - the previous
    /// account's block list says nothing about this one.
    @Test
    func switchingUsersReArmsFailClosedRendering() async {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        await repository.suspendFetches()
        let hydration = Task { await store.hydrate(for: "other-viewer") }
        while !(await repository.hasStartedFetch(2)) {
            await Task.yield()
        }

        #expect(store.isBlockListHydrated == false)
        #expect(store.moderate(otherClimber(), isCurrentUser: false).isHidden)

        await repository.releaseFetch(2, returning: [])
        await hydration.value
    }

    @Test
    func moderationRejectsAnEmptyUserIdInsteadOfReachingTheRepository() async {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        await #expect(throws: ModerationStoreError.self) {
            try await store.block(blockerUserId: "viewer", blockedUserId: "")
        }
        await #expect(throws: ModerationStoreError.self) {
            try await store.unblock(blockerUserId: "viewer", blockedUserId: " ")
        }
        await #expect(throws: ModerationStoreError.self) {
            try await store.report(
                reporterUserId: "viewer",
                reportedUserId: "",
                reason: .harassment,
                source: .profile
            )
        }

        #expect(await repository.blockCalls.isEmpty)
        #expect(await repository.unblockCalls.isEmpty)
        #expect(await repository.reportCalls.isEmpty)
    }

    /// Repeated renders of unchanged rows must not re-derive the whole board.
    @Test
    func moderatedCollectionsAreCachedUntilTheBlockListChanges() async throws {
        let repository = RepositorySpy()
        let store = makeStore(repository: repository)
        await store.hydrate(for: "viewer")

        let entries = (0..<3).map { index in
            LeaderboardEntry(
                userId: "climber-\(index)",
                displayName: "Climber \(index)",
                rank: index + 1,
                value: Double(index),
                formattedValue: "\(index)"
            )
        }

        #expect(store.moderate(entries) == store.moderate(entries))

        let visible = try #require(store.moderate(entries).first)
        #expect(visible.identity.isHidden == false)

        try await store.block(
            blockerUserId: "viewer",
            blockedUserId: "climber-0"
        )
        let masked = try #require(store.moderate(entries).first)
        #expect(masked.identity.isHidden)
    }

    private func makeStore(
        repository: RepositorySpy,
        serverSyncMarker: ServerSyncMarkerSpy = ServerSyncMarkerSpy()
    ) -> ModerationStore {
        ModerationStore(
            repository: repository,
            serverSyncMarker: serverSyncMarker
        )
    }

    private func otherClimber() -> ProfileUserIdentity {
        ProfileUserIdentity(
            userId: "other-user",
            displayName: "Raw Name",
            photoURL: URL(string: "https://example.com/raw.jpg")
        )
    }
}
