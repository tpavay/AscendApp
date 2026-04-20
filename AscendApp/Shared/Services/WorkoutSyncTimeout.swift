import Foundation

enum WorkoutSyncTimeoutError: LocalizedError {
    case operationTimedOut

    var errorDescription: String? {
        switch self {
        case .operationTimedOut:
            return "The workout sync request timed out."
        }
    }
}

func withWorkoutSyncTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw WorkoutSyncTimeoutError.operationTimedOut
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
