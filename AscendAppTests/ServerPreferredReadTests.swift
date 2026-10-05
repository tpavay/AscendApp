import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The one shared server-preferred read: when it asks again, when it does not, and what it
/// hands back when the server never answers.
struct ServerPreferredReadTests {
    @Test
    func aFirstAnswerIsReturnedWithoutWaitingOrRecording() async throws {
        let script = ReadScript(server: [.success("server")])

        let outcome = await script.run(policy: .cacheFallback)

        #expect(try outcome.result.get() == "server")
        #expect(outcome.isFromCache == false)
        #expect(outcome.failures.isEmpty)
        #expect(script.attempts == [.server])
        #expect(script.waits.isEmpty)
    }

    /// The 2026-10-03 case: the stream is down for a moment while the phone is connected.
    @Test
    func anUnreachableServerIsAskedOnceMoreAfterTheQuietWait() async throws {
        let script = ReadScript(server: [.failure(Firestore.error(.unavailable)), .success("server")])

        let outcome = await script.run(policy: .serverRequired)

        #expect(try outcome.result.get() == "server")
        #expect(outcome.isFromCache == false)
        #expect(outcome.failures.map(\.failureClass) == [.unreachable])
        #expect(script.attempts == [.server, .server])
        #expect(script.waits == [ServerPreferredRead.defaultRetryDelay])
    }

    @Test
    func aServerUnreachableTwiceThrowsWhenTheServerIsRequired() async {
        let script = ReadScript(server: [
            .failure(Firestore.error(.unavailable)),
            .failure(Firestore.error(.deadlineExceeded))
        ])

        let outcome = await script.run(policy: .serverRequired)

        #expect(Firestore.code(of: outcome.result) == FirestoreErrorCode.deadlineExceeded.rawValue)
        #expect(outcome.isFromCache == false)
        #expect(outcome.failures.map(\.failureClass) == [.unreachable, .unreachable])
        // One quiet retry, never a loop, and the cache is never consulted.
        #expect(script.attempts == [.server, .server])
        #expect(script.waits.count == 1)
    }

    @Test
    func aServerUnreachableTwiceFallsBackToTheDevicesCopyAndSaysSo() async throws {
        let script = ReadScript(
            server: [.failure(Firestore.error(.unavailable)), .failure(Firestore.error(.unavailable))],
            cache: .success("cached")
        )

        let outcome = await script.run(policy: .cacheFallback)

        #expect(try outcome.result.get() == "cached")
        #expect(outcome.isFromCache)
        #expect(outcome.failures.count == 2)
        #expect(script.attempts == [.server, .server, .cache])
    }

    @Test
    func aFailedCacheReadSurfacesTheServersError() async {
        let script = ReadScript(
            server: [.failure(Firestore.error(.unavailable)), .failure(Firestore.error(.unavailable))],
            cache: .failure(Firestore.error(.unavailable))
        )

        let outcome = await script.run(policy: .cacheFallback)

        #expect(Firestore.code(of: outcome.result) == FirestoreErrorCode.unavailable.rawValue)
        #expect(outcome.isFromCache == false)
    }

    /// Fail fast with no network path: there is no stream two seconds could bring back.
    @Test
    func noNetworkPathSkipsTheQuietRetry() async {
        let script = ReadScript(server: [.failure(Firestore.error(.unavailable))])

        let outcome = await script.run(policy: .serverRequired, hasNetworkPath: false)

        #expect(Firestore.code(of: outcome.result) == FirestoreErrorCode.unavailable.rawValue)
        #expect(script.attempts == [.server])
        #expect(script.waits.isEmpty)
    }

    @Test
    func aPolicyWithoutTheQuietRetryAsksOnce() async {
        let script = ReadScript(server: [.failure(Firestore.error(.unavailable))])

        let outcome = await script.run(policy: ServerPreferredReadPolicy(retriesUnreachable: false))

        #expect(outcome.failures.count == 1)
        #expect(script.attempts == [.server])
        #expect(script.waits.isEmpty)
    }

    /// The 2026-09-25 case: the grant is missing, reconciliation restores it, the read succeeds.
    @Test
    func aRefusalIsHealedOnceAndAskedAgainWithoutWaiting() async throws {
        let script = ReadScript(server: [.failure(Firestore.error(.permissionDenied)), .success("server")])

        let outcome = await script.run(policy: .cacheFallback, refusalRecovery: .heals)

        #expect(try outcome.result.get() == "server")
        #expect(outcome.attemptedRefusalRecovery)
        #expect(script.recoveryCalls == 1)
        #expect(script.attempts == [.server, .server])
        #expect(script.waits.isEmpty)
    }

    @Test
    func aRefusalThatSurvivesRecoveryIsNotHealedTwice() async {
        let script = ReadScript(server: [
            .failure(Firestore.error(.permissionDenied)),
            .failure(Firestore.error(.permissionDenied))
        ])

        let outcome = await script.run(policy: .serverRequired, refusalRecovery: .heals)

        #expect(Firestore.code(of: outcome.result) == FirestoreErrorCode.permissionDenied.rawValue)
        #expect(outcome.failures.map(\.failureClass) == [.refused, .refused])
        #expect(script.recoveryCalls == 1)
        #expect(script.attempts == [.server, .server])
    }

    /// No entitlement on the device means the refusal is the paywall working.
    @Test
    func aRefusalWithNothingToRecoverIsNotAskedAgain() async {
        let script = ReadScript(server: [.failure(Firestore.error(.permissionDenied))])

        let outcome = await script.run(policy: .serverRequired, refusalRecovery: .declines)

        #expect(outcome.attemptedRefusalRecovery)
        #expect(script.recoveryCalls == 1)
        #expect(script.attempts == [.server])
    }

    @Test
    func aRefusalWithNoRecoveryIsNeitherRetriedNorWaitedOn() async {
        let script = ReadScript(server: [.failure(Firestore.error(.permissionDenied))])

        let outcome = await script.run(policy: .serverRequired)

        #expect(outcome.attemptedRefusalRecovery == false)
        #expect(script.attempts == [.server])
        #expect(script.waits.isEmpty)
    }

    /// A missing index does not fix itself in two seconds.
    @Test
    func anUnexpectedFailureIsNeverRetried() async {
        let script = ReadScript(server: [.failure(Firestore.error(.failedPrecondition))])

        let outcome = await script.run(policy: .serverRequired, refusalRecovery: .heals)

        #expect(outcome.failures.map(\.failureClass) == [.unexpected])
        #expect(script.attempts == [.server])
        #expect(script.recoveryCalls == 0)
        #expect(script.waits.isEmpty)
    }

    /// Each remedy runs once, so the worst case is bounded at three server attempts.
    @Test
    func theQuietRetryAndTheRefusalRecoveryEachRunAtMostOnce() async {
        let script = ReadScript(server: [
            .failure(Firestore.error(.unavailable)),
            .failure(Firestore.error(.permissionDenied)),
            .failure(Firestore.error(.unavailable))
        ])

        let outcome = await script.run(policy: .serverRequired, refusalRecovery: .heals)

        #expect(outcome.failures.map(\.failureClass) == [.unreachable, .refused, .unreachable])
        #expect(script.attempts == [.server, .server, .server])
        #expect(script.waits.count == 1)
        #expect(script.recoveryCalls == 1)
    }

    @Test
    func theServerRequiredFormReturnsTheValueOrThrowsTheServersError() async throws {
        let value = try await ServerPreferredRead.serverRequired { "server" }
        #expect(value == "server")

        await #expect(throws: (any Error).self) {
            try await ServerPreferredRead.serverRequired(quietRetry: false) { () -> String in
                throw Firestore.error(.permissionDenied)
            }
        }
    }
}

/// A read that fails the way the script says, and remembers how it was asked.
private final class ReadScript: @unchecked Sendable {
    enum RefusalRecovery {
        case none
        case heals
        case declines
    }

    private var server: [Result<String, any Error>]
    private let cache: Result<String, any Error>?
    private let lock = NSLock()
    private var recordedWaits: [Duration] = []
    private(set) var attempts: [ServerPreferredReadAttempt] = []
    private(set) var recoveryCalls = 0

    var waits: [Duration] {
        lock.withLock { recordedWaits }
    }

    init(server: [Result<String, any Error>], cache: Result<String, any Error>? = nil) {
        self.server = server
        self.cache = cache
    }

    func run(
        policy: ServerPreferredReadPolicy,
        hasNetworkPath: Bool = true,
        refusalRecovery: RefusalRecovery = .none
    ) async -> ServerPreferredReadOutcome<String> {
        let recover: (() async -> Bool)? = switch refusalRecovery {
        case .none: nil
        case .heals: { self.recoveryCalls += 1; return true }
        case .declines: { self.recoveryCalls += 1; return false }
        }

        return await ServerPreferredRead.run(
            policy: policy,
            hasNetworkPath: { hasNetworkPath },
            wait: { duration in self.lock.withLock { self.recordedWaits.append(duration) } },
            recoverRefusal: recover,
            read: { attempt in
                self.attempts.append(attempt)
                switch attempt {
                case .server:
                    return try self.server.removeFirst().get()
                case .cache:
                    return try #require(self.cache).get()
                }
            }
        )
    }
}

extension Firestore {
    /// An error shaped the way the Firestore SDK reports one.
    static func error(_ code: FirestoreErrorCode.Code) -> NSError {
        NSError(domain: FirestoreErrorDomain, code: code.rawValue)
    }

    static func code<Value>(of result: Result<Value, any Error>) -> Int? {
        guard case .failure(let error) = result else { return nil }
        return (error as NSError).code
    }
}
