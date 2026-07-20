import CoreBluetooth
import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct HeartRateMonitorServiceTests {
    @Test("Session auto-connect settles within the connection bound")
    func autoConnectTimesOut() async throws {
        let suiteName = "HeartRateMonitorServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deviceID = UUID()
        rememberDevice(id: deviceID, in: defaults)
        let client = FakeBluetoothHeartRateClient()
        var requestedDuration: Duration?
        let service = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { duration in
                requestedDuration = duration
            }
        )

        service.autoConnectIfRemembered()
        await Task.yield()

        #expect(HeartRateMonitorService.connectTimeout == .seconds(15))
        #expect(requestedDuration == .seconds(15))
        #expect(service.connectionState == .failed)
        #expect(client.disconnectCallCount == 1)
    }

    @Test("Session auto-connect settles when the strap connects")
    func autoConnectSettlesWhenConnected() async throws {
        let suiteName = "HeartRateMonitorServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deviceID = UUID()
        rememberDevice(id: deviceID, in: defaults)
        let client = FakeBluetoothHeartRateClient()
        let service = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { duration in
                try await Task.sleep(for: duration)
            }
        )

        service.autoConnectIfRemembered()
        client.emit(.connected(id: deviceID, name: "Test Strap"))
        await Task.yield()

        #expect(service.connectionState == .connected)
        #expect(service.didLastConnectAttemptTimeOut == false)
    }

    @Test("Heart-rate failure never delays step-tracking start")
    func heartRateFailureDoesNotDelaySessionStart() throws {
        let suiteName = "HeartRateMonitorServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deviceID = UUID()
        rememberDevice(id: deviceID, in: defaults)
        let client = FakeBluetoothHeartRateClient()
        let monitor = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { _ in }
        )
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.startError = HeadphoneMotionSessionError.motionUnavailable
        var monitorStateWhenStepTrackingStarted: HeartRateMonitorService.ConnectionState?
        motionSession.onStartRecording = {
            monitorStateWhenStepTrackingStarted = monitor.connectionState
        }
        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: motionSession,
            draftStore: ActiveHeadphoneWorkoutDraftStore(userDefaults: defaults),
            heartRateMonitor: monitor
        )

        viewModel.start(modelContext: ModelContext(container))

        #expect(motionSession.startRecordingCallCount == 1)
        #expect(monitorStateWhenStepTrackingStarted == .connecting)
    }

    private func rememberDevice(id: UUID, in defaults: UserDefaults) {
        defaults.set(id.uuidString, forKey: "heartRateMonitor.rememberedDeviceID")
        defaults.set("Test Strap", forKey: "heartRateMonitor.rememberedDeviceName")
    }
}
