import CoreBluetooth
import Foundation
import Observation

/// App-facing facade for live heart-rate monitors.
///
/// Owns the Bluetooth client, remembers the paired device across launches,
/// auto-reconnects at session start, and exposes observable connection +
/// measurement state for SwiftUI. This is the seam future heart-rate sources
/// (Apple Watch companion via HealthKit mirroring) plug into: consumers read
/// `currentMeasurement`/`connectionState` and never talk to a transport.
@MainActor
@Observable
final class HeartRateMonitorService {
    static let shared = HeartRateMonitorService()

    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
    }

    struct RememberedDevice: Equatable {
        let id: UUID
        let name: String
    }

    /// A reading older than this is treated as stale: chest straps notify at
    /// ~1 Hz, and BLE has no "signal lost" push — silence is the only signal.
    static let sampleFreshnessWindow: TimeInterval = 5
    /// connect() never times out natively; without this a strap whose slots
    /// are held by another device (Polar H10 ships single-slot) hangs forever.
    private static let connectTimeout: TimeInterval = 15

    private static let rememberedIDDefaultsKey = "heartRateMonitor.rememberedDeviceID"
    private static let rememberedNameDefaultsKey = "heartRateMonitor.rememberedDeviceName"

    private(set) var availability: BluetoothHeartRateAvailability = .unknown
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var discoveredDevices: [BluetoothHeartRateDeviceCandidate] = []
    private(set) var currentMeasurement: HeartRateMeasurement?
    private(set) var connectedDeviceName: String?
    private(set) var didLastConnectAttemptTimeOut = false
    private(set) var rememberedDevice: RememberedDevice?

    @ObservationIgnored private var client: BluetoothHeartRateClient?
    @ObservationIgnored private var connectTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let idString = userDefaults.string(forKey: Self.rememberedIDDefaultsKey),
           let id = UUID(uuidString: idString) {
            let name = userDefaults.string(forKey: Self.rememberedNameDefaultsKey) ?? "Heart Rate Monitor"
            rememberedDevice = RememberedDevice(id: id, name: name)
        }
    }

    /// Bluetooth permission state, readable without triggering the prompt.
    var authorization: CBManagerAuthorization {
        CBCentralManager.authorization
    }

    var isConnected: Bool {
        connectionState == .connected
    }

    /// The latest reading if it arrived recently enough to trust for display.
    var freshMeasurement: HeartRateMeasurement? {
        guard let currentMeasurement,
              Date().timeIntervalSince(currentMeasurement.receivedAt) <= Self.sampleFreshnessWindow else {
            return nil
        }
        return currentMeasurement
    }

    // MARK: - Pairing flow (manage sheet)

    /// Starts discovery. First call creates the Bluetooth central, which
    /// triggers the system permission prompt — only call from a
    /// user-initiated pairing flow.
    func startPairingScan() {
        didLastConnectAttemptTimeOut = false
        discoveredDevices = []
        if connectionState != .connected {
            connectionState = .scanning
        }
        ensureClient().startScanning()
    }

    func stopPairingScan() {
        client?.stopScanning()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(to candidate: BluetoothHeartRateDeviceCandidate) {
        remember(id: candidate.id, name: candidate.name)
        beginConnection(to: candidate.id)
    }

    func disconnect() {
        connectTimeoutTask?.cancel()
        client?.disconnect()
        connectionState = .disconnected
        connectedDeviceName = nil
        currentMeasurement = nil
    }

    /// Disconnects and stops auto-connecting to the remembered device.
    func forgetDevice() {
        disconnect()
        rememberedDevice = nil
        userDefaults.removeObject(forKey: Self.rememberedIDDefaultsKey)
        userDefaults.removeObject(forKey: Self.rememberedNameDefaultsKey)
    }

    // MARK: - Session integration

    /// Silently connects to the remembered device if one exists. Called at
    /// live-session start so a worn strap "just works" with no UI. No-op when
    /// nothing was ever paired or Bluetooth permission was never granted, so
    /// it can never trigger a permission prompt mid-session.
    func autoConnectIfRemembered() {
        guard let rememberedDevice,
              authorization == .allowedAlways,
              connectionState == .disconnected else {
            return
        }
        beginConnection(to: rememberedDevice.id, timesOut: false)
    }

    // MARK: - Internals

    private func beginConnection(to id: UUID, timesOut: Bool = true) {
        didLastConnectAttemptTimeOut = false
        connectionState = .connecting
        let client = ensureClient()
        client.stopScanning()
        client.connect(to: id)

        connectTimeoutTask?.cancel()
        guard timesOut else { return }
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.connectTimeout))
            guard !Task.isCancelled, let self, self.connectionState == .connecting else { return }
            self.client?.disconnect()
            self.connectionState = .disconnected
            self.didLastConnectAttemptTimeOut = true
        }
    }

    private func remember(id: UUID, name: String) {
        rememberedDevice = RememberedDevice(id: id, name: name)
        userDefaults.set(id.uuidString, forKey: Self.rememberedIDDefaultsKey)
        userDefaults.set(name, forKey: Self.rememberedNameDefaultsKey)
    }

    private func ensureClient() -> BluetoothHeartRateClient {
        if let client {
            return client
        }
        let newClient = BluetoothHeartRateClient { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        client = newClient
        return newClient
    }

    private func handle(_ event: BluetoothHeartRateClientEvent) {
        switch event {
        case .availabilityChanged(let availability):
            self.availability = availability
            if availability != .poweredOn, connectionState == .connected {
                connectionState = .disconnected
                connectedDeviceName = nil
            }

        case .discovered(let candidate):
            if let index = discoveredDevices.firstIndex(where: { $0.id == candidate.id }) {
                discoveredDevices[index] = candidate
            } else {
                discoveredDevices.append(candidate)
            }
            discoveredDevices.sort { $0.rssi > $1.rssi }

        case .connected(let id, let name):
            connectTimeoutTask?.cancel()
            connectionState = .connected
            connectedDeviceName = name
            didLastConnectAttemptTimeOut = false
            if rememberedDevice?.id == id {
                remember(id: id, name: name)
            }

        case .disconnected(let id, let wasRequested):
            currentMeasurement = nil
            guard !wasRequested else { return }
            connectedDeviceName = nil
            // The client keeps a persistent reconnect pending for unexpected
            // drops; reflect that so the UI can show "reconnecting".
            connectionState = rememberedDevice?.id == id ? .connecting : .disconnected

        case .connectionFailed:
            connectTimeoutTask?.cancel()
            connectionState = .disconnected
            connectedDeviceName = nil

        case .measurement(let measurement):
            currentMeasurement = measurement
        }
    }
}
