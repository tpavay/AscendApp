import CoreBluetooth
import Foundation

/// Bluetooth radio availability as seen by the client.
enum BluetoothHeartRateAvailability: Equatable, Sendable {
    case unknown
    case poweredOn
    case poweredOff
    case unauthorized
    case unsupported
}

/// A nearby device advertising the standard Heart Rate Service.
struct BluetoothHeartRateDeviceCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Events emitted by `BluetoothHeartRateClient`. Delivered on the client's
/// private Bluetooth queue; the consumer is responsible for marshaling.
enum BluetoothHeartRateClientEvent: Sendable {
    case availabilityChanged(BluetoothHeartRateAvailability)
    case discovered(BluetoothHeartRateDeviceCandidate)
    case connected(id: UUID, name: String)
    case disconnected(id: UUID, wasRequested: Bool)
    case connectionFailed(id: UUID)
    case measurement(HeartRateMeasurement)
}

/// CoreBluetooth central for the standard BLE Heart Rate Profile.
///
/// One implementation covers every compliant device — Polar/Morpheus/Garmin
/// chest straps, WHOOP in broadcast mode, gym equipment — because they all
/// advertise Heart Rate Service 0x180D and notify on characteristic 0x2A37.
///
/// All mutable state is confined to `queue`: public methods hop onto it and
/// CoreBluetooth delivers delegate callbacks on it, so the class is safe to
/// share despite the compiler being unable to prove it (`@unchecked Sendable`).
final class BluetoothHeartRateClient: NSObject, @unchecked Sendable {
    // Instance constants rather than statics: CBUUID is not Sendable, and
    // this class's state is already confined to its Bluetooth queue.
    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")

    private let queue = DispatchQueue(label: "com.ascend.heart-rate-ble")
    private let onEvent: @Sendable (BluetoothHeartRateClientEvent) -> Void

    private var central: CBCentralManager?
    private var isScanning = false
    private var targetPeripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    /// Set when the app asked for the disconnect, so unexpected drops can
    /// auto-reconnect while intentional ones stay disconnected.
    private var isDisconnectRequested = false
    /// Peripheral to reconnect to whenever it comes back in range.
    private var reconnectIdentifier: UUID?

    init(onEvent: @escaping @Sendable (BluetoothHeartRateClientEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    // MARK: - Public API (thread-safe; hops to the Bluetooth queue)

    /// Creates the central manager, which triggers the system Bluetooth
    /// permission prompt on first use. Call from a user-initiated flow.
    func prepare() {
        queue.async { [self] in
            ensureCentral()
        }
    }

    func startScanning() {
        queue.async { [self] in
            isScanning = true
            scanIfPoweredOn()
        }
    }

    func stopScanning() {
        queue.async { [self] in
            isScanning = false
            guard let central, central.state == .poweredOn else { return }
            central.stopScan()
        }
    }

    func connect(to identifier: UUID) {
        queue.async { [self] in
            isDisconnectRequested = false
            reconnectIdentifier = identifier
            connectOnQueue(to: identifier)
        }
    }

    func disconnect() {
        queue.async { [self] in
            isDisconnectRequested = true
            reconnectIdentifier = nil
            guard let central, let peripheral = targetPeripheral else { return }
            central.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - Queue-confined implementation

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue)
        }
    }

    private func scanIfPoweredOn() {
        ensureCentral()
        guard let central, central.state == .poweredOn, isScanning else { return }
        central.scanForPeripherals(
            withServices: [heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connectOnQueue(to identifier: UUID) {
        ensureCentral()
        guard let central else { return }
        guard central.state == .poweredOn else { return }

        // Prefer a peripheral the SYSTEM already holds a connection to (e.g.
        // another app on this phone is reading the same strap) — iOS shares
        // one physical link across apps, so this connect completes instantly
        // and consumes no extra slot on the device.
        let systemConnected = central
            .retrieveConnectedPeripherals(withServices: [heartRateServiceUUID])
            .first { $0.identifier == identifier }

        let peripheral: CBPeripheral?
        if let systemConnected {
            peripheral = systemConnected
        } else if let discovered = discoveredPeripherals[identifier] {
            peripheral = discovered
        } else {
            // A remembered device that isn't in the discovery cache. connect()
            // on a retrieved peripheral is persistent: iOS completes it
            // whenever the device starts advertising, which is what makes
            // strap-on-and-go auto-connect work.
            peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first
        }

        guard let peripheral else {
            onEvent(.connectionFailed(id: identifier))
            return
        }

        discoveredPeripherals[identifier] = peripheral
        targetPeripheral = peripheral
        central.connect(peripheral, options: nil)
    }

    private static func availability(for state: CBManagerState) -> BluetoothHeartRateAvailability {
        switch state {
        case .poweredOn:
            return .poweredOn
        case .poweredOff:
            return .poweredOff
        case .unauthorized:
            return .unauthorized
        case .unsupported:
            return .unsupported
        case .unknown, .resetting:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothHeartRateClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onEvent(.availabilityChanged(Self.availability(for: central.state)))

        guard central.state == .poweredOn else {
            // Peripheral objects are invalidated when the radio leaves
            // poweredOn (e.g. Bluetooth toggled off) — drop them so the next
            // connect retrieves fresh instances instead of dead references.
            discoveredPeripherals.removeAll()
            targetPeripheral = nil
            return
        }
        scanIfPoweredOn()
        if let reconnectIdentifier, targetPeripheral?.state != .connected {
            connectOnQueue(to: reconnectIdentifier)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Heart Rate Monitor"
        onEvent(
            .discovered(
                BluetoothHeartRateDeviceCandidate(
                    id: peripheral.identifier,
                    name: name,
                    rssi: RSSI.intValue
                )
            )
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([heartRateServiceUUID])
        onEvent(.connected(id: peripheral.identifier, name: peripheral.name ?? "Heart Rate Monitor"))
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onEvent(.connectionFailed(id: peripheral.identifier))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let wasRequested = isDisconnectRequested
        onEvent(.disconnected(id: peripheral.identifier, wasRequested: wasRequested))

        if wasRequested {
            targetPeripheral = nil
            isDisconnectRequested = false
        } else if let reconnectIdentifier {
            // Unexpected drop (strap out of range, battery pull): keep a
            // persistent reconnect pending so HR resumes when it returns.
            connectOnQueue(to: reconnectIdentifier)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothHeartRateClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) else {
            return
        }
        peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristic = service.characteristics?.first(
            where: { $0.uuid == heartRateMeasurementUUID }
        ) else { return }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == heartRateMeasurementUUID,
              error == nil,
              let data = characteristic.value,
              let measurement = HeartRateMeasurementParser.parse(data) else {
            return
        }
        onEvent(.measurement(measurement))
    }
}
