import Foundation
import Network
import Observation

/// The one question the sync coordinator asks about connectivity.
///
/// A protocol rather than the concrete service so the coordinator can be tested without a real
/// `NWPathMonitor`, while the app still has exactly one source of connectivity truth - this is
/// dependency injection, not a second detector.
///
/// A satisfied path is permission to try, never proof that Firebase is reachable. Server results
/// stay authoritative.
@MainActor
protocol WorkoutSyncConnectivityProviding {
    var isConnected: Bool { get }
}

@MainActor
@Observable
final class NetworkConnectivityService: WorkoutSyncConnectivityProviding {
    static let shared = NetworkConnectivityService()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ascend.network-connectivity")

    private(set) var isConnected = true
    private(set) var isExpensive = false
    private(set) var isConstrained = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path: path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    private func apply(path: NWPath) {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
    }
}
