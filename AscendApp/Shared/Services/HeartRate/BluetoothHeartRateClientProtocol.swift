import Foundation

protocol BluetoothHeartRateClientProtocol: AnyObject {
    func startScanning()
    func stopScanning()
    func connect(to identifier: UUID)
    func disconnect()
}

extension BluetoothHeartRateClient: BluetoothHeartRateClientProtocol {}
