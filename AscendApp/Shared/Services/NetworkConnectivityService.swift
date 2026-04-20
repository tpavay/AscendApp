import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkConnectivityService {
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
