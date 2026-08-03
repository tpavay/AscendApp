import Foundation

enum RemoteSyncTimeoutError: LocalizedError {
    case operationTimedOut

    var errorDescription: String? {
        switch self {
        case .operationTimedOut:
            return "The cloud backup request timed out."
        }
    }
}

/// Bounds one remote backup call.
///
/// Shared by every sync coordinator rather than reimplemented per feature: a
/// second timeout policy is a second set of numbers to keep in step, and the
/// one thing every one of these calls has in common is that it must not hold
/// the queue open forever.
func withRemoteSyncTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw RemoteSyncTimeoutError.operationTimedOut
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
