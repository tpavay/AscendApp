import Foundation
@testable import AscendApp

final class FakeBluetoothHeartRateClient: BluetoothHeartRateClientProtocol {
    var onEvent: (@Sendable (BluetoothHeartRateClientEvent) -> Void)?
    private(set) var connectedIdentifiers: [UUID] = []
    private(set) var disconnectCallCount = 0

    func startScanning() {}

    func stopScanning() {}

    func connect(to identifier: UUID) {
        connectedIdentifiers.append(identifier)
    }

    func disconnect() {
        disconnectCallCount += 1
    }

    func emit(_ event: BluetoothHeartRateClientEvent) {
        onEvent?(event)
    }
}
