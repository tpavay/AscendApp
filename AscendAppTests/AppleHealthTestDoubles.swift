import Foundation
import HealthKit
@testable import AscendApp

// Shared Apple Health test doubles.
//
// They previously lived alongside the enrichment coordinator's own tests. That coordinator
// was superseded by `AppleHealthEnrichmentService` and deleted, but these doubles are used by
// the account-deletion gate, Home-entry cost, and removal-evidence suites, so they were kept
// rather than deleted with it.


@MainActor
final class StubMetricsReader: HealthKitMetricsReading {
    private var responses: [WorkoutMetrics]
    private(set) var requestedRanges: [ClosedRange<Date>] = []

    init(responses: [WorkoutMetrics]) {
        self.responses = responses
    }

    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        requestedRanges.append(dateRange)
        guard !responses.isEmpty else { return WorkoutMetrics() }
        return responses.removeFirst()
    }
}

@MainActor
final class StubAuthorizationController: HealthKitAuthorizationControlling {
    var isHealthDataAvailable = true
    var lastPermissionErrorMessage: String?
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary

    var hasRequestedAuthorization: Bool {
        HealthKitSyncState.hasRequestedAuthorization
    }

    var connectionState: AppleHealthConnectionState {
        guard isHealthDataAvailable else { return .unavailable }
        guard hasRequestedAuthorization else { return .neverConnected }
        return .connected
    }

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool {
        HealthKitSyncState.hasRequestedAuthorization = true
        return true
    }
}

struct HealthKitSyncStateSnapshot {
    private let hasRequestedAuthorization: Bool

    static func capture() -> HealthKitSyncStateSnapshot {
        HealthKitSyncStateSnapshot(
            hasRequestedAuthorization: HealthKitSyncState.hasRequestedAuthorization
        )
    }

    func restore() {
        HealthKitSyncState.hasRequestedAuthorization = hasRequestedAuthorization
    }
}
