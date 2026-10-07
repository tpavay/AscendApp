import Foundation

/// The one way Ascend asks Firestore for the server's answer rather than whatever is cached.
///
/// A read with source `.server` fails at once with `unavailable` whenever the SDK has marked
/// itself offline - one failed stream attempt is enough - even while the phone has a working
/// network path, because `NetworkConnectivityService` sees the path and not Firestore's own
/// stream. Every forced read therefore failed together during a network handoff, and each
/// feature reported it in its own words.
///
/// So the mechanics live here, once: ask the server; on an unreachable-class failure wait
/// briefly and ask once more; on a refusal let the caller re-derive access and ask once more;
/// then either hand back the device's last copy, flagged, or the error. Features decide what the
/// climber is told - never whether or how to retry. Do not add a second retry beside this one.
enum ServerPreferredRead {
    static let defaultRetryDelay: Duration = .seconds(2)

    /// Runs `read` until the server answers or the policy is spent.
    ///
    /// At most three server attempts: the first, one after the quiet retry, and one after a
    /// healed refusal. Runs on the caller's isolation, so `read` may capture actor state.
    ///
    /// - Parameters:
    ///   - hasNetworkPath: The app-wide connectivity answer. With no network path there is no
    ///     stream to wait for, so the quiet retry is skipped and the failure surfaces at once.
    ///   - wait: The delay before the quiet retry. Injected so tests do not sleep.
    ///   - recoverRefusal: Called once after a refused attempt. Returns whether access was
    ///     re-derived and the read is worth asking again.
    static func run<Value>(
        isolation: isolated (any Actor)? = #isolation,
        policy: ServerPreferredReadPolicy,
        hasNetworkPath: @Sendable () async -> Bool = ServerPreferredRead.appHasNetworkPath,
        wait: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        recoverRefusal: (() async -> Bool)? = nil,
        read: (ServerPreferredReadAttempt) async throws -> Value
    ) async -> ServerPreferredReadOutcome<Value> {
        var failures: [ServerReadFailure] = []
        var didRetryUnreachable = false
        var didAttemptRefusalRecovery = false

        while true {
            let failure: ServerReadFailure
            do {
                let value = try await read(.server)
                return ServerPreferredReadOutcome(
                    result: .success(value),
                    isFromCache: false,
                    failures: failures,
                    attemptedRefusalRecovery: didAttemptRefusalRecovery
                )
            } catch {
                failure = ServerReadFailure(error)
            }
            failures.append(failure)

            switch failure.failureClass {
            case .unreachable:
                // A cancelled caller is not waiting for an answer, and a phone with no network
                // path has no stream that two seconds could bring back.
                if policy.retriesUnreachable,
                   !didRetryUnreachable,
                   !Task.isCancelled,
                   await hasNetworkPath() {
                    didRetryUnreachable = true
                    await wait(policy.retryDelay)
                    continue
                }
            case .refused:
                if let recoverRefusal, !didAttemptRefusalRecovery {
                    didAttemptRefusalRecovery = true
                    if await recoverRefusal() { continue }
                }
            case .unexpected:
                break
            }

            if policy.fallsBackToCache, let cached = try? await read(.cache) {
                return ServerPreferredReadOutcome(
                    result: .success(cached),
                    isFromCache: true,
                    failures: failures,
                    attemptedRefusalRecovery: didAttemptRefusalRecovery
                )
            }

            return ServerPreferredReadOutcome(
                result: .failure(failure.error),
                isFromCache: false,
                failures: failures,
                attemptedRefusalRecovery: didAttemptRefusalRecovery
            )
        }
    }

    /// The app-wide connectivity answer. A named function rather than a closure literal in the
    /// default argument: a literal reading main-actor state makes the default itself main-actor
    /// isolated, and every forced read would then hop to the main actor just to build it.
    @Sendable
    static func appHasNetworkPath() async -> Bool {
        await NetworkConnectivityService.shared.isConnected
    }

    /// The server's answer or a thrown error, with the one quiet retry in between.
    ///
    /// - Parameter quietRetry: Pass `false` only where the caller already has an immediate,
    ///   designed answer for an unreachable server and waiting would cost the climber more than
    ///   the retry could win back.
    static func serverRequired<Value>(
        isolation: isolated (any Actor)? = #isolation,
        quietRetry: Bool = true,
        _ read: () async throws -> Value
    ) async throws -> Value {
        try await run(
            isolation: isolation,
            policy: ServerPreferredReadPolicy(retriesUnreachable: quietRetry)
        ) { _ in
            try await read()
        }.result.get()
    }
}
