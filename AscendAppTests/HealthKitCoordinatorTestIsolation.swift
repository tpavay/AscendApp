import Foundation

@MainActor
final class HealthKitCoordinatorTestIsolation {
  static let shared = HealthKitCoordinatorTestIsolation()

  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  private init() {}

  func run(_ operation: @MainActor () async throws -> Void) async rethrows {
    await acquire()
    defer { releaseNext() }

    try await operation()
  }

  private func acquire() async {
    if isLocked {
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    } else {
      isLocked = true
    }
  }

  private func releaseNext() {
    guard waiters.isEmpty == false else {
      isLocked = false
      return
    }

    waiters.removeFirst().resume()
  }
}
