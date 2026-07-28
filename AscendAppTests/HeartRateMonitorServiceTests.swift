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
        #expect(service.connectionState == .connecting)
        await Task.yield()

        #expect(HeartRateMonitorService.connectTimeout <= .seconds(15))
        #expect(requestedDuration == HeartRateMonitorService.connectTimeout)
        #expect(service.connectionState == .failed)
        #expect(service.didLastConnectAttemptTimeOut)
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
            heartRateRecorder: LiveHeartRateRecorder(sources: [monitor]),
            heartRateMonitor: monitor
        )

        viewModel.start(modelContext: ModelContext(container))

        #expect(motionSession.startRecordingCallCount == 1)
        #expect(monitorStateWhenStepTrackingStarted == .connecting)
    }

    @Test("An unexpected mid-session drop keeps the transport reconnecting")
    func midSessionDropPreservesPersistentReconnect() async throws {
        let suiteName = "HeartRateMonitorServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deviceID = UUID()
        rememberDevice(id: deviceID, in: defaults)
        let client = FakeBluetoothHeartRateClient()
        var sleepCallCount = 0
        let service = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { duration in
                sleepCallCount += 1
                try await Task.sleep(for: duration)
            }
        )

        service.autoConnectIfRemembered()
        client.emit(.connected(id: deviceID, name: "Test Strap"))
        client.emit(
            .measurement(
                HeartRateMeasurement(beatsPerMinute: 142, sensorContact: .detected, receivedAt: Date())
            )
        )
        await settle()
        client.emit(.disconnected(id: deviceID, wasRequested: false))
        await settle()

        #expect(service.connectionState == .reconnecting)
        #expect(client.disconnectCallCount == 0)
        #expect(service.didLastConnectAttemptTimeOut == false)
        #expect(sleepCallCount == 1)
        #expect(service.currentMeasurement == nil)
    }

    @Test("A mid-session drop leaves an honest gap in the stored heart-rate series")
    func midSessionDropLeavesGapInStoredSeries() async throws {
        let suiteName = "HeartRateMonitorServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deviceID = UUID()
        rememberDevice(id: deviceID, in: defaults)
        let client = FakeBluetoothHeartRateClient()
        // Freshness is judged against a pinned clock: the reading below must
        // stay trusted no matter how long a loaded CI runner takes to hop
        // between the emit and the assertion.
        let readAt = Date(timeIntervalSince1970: 1_780_000_000)
        let monitor = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { duration in
                try await Task.sleep(for: duration)
            },
            now: { readAt }
        )
        let recorder = LiveHeartRateRecorder(sources: [monitor])
        let motionSession = FakeHeadphoneMotionSession()
        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            motionSession: motionSession,
            draftStore: ActiveHeadphoneWorkoutDraftStore(userDefaults: defaults),
            heartRateRecorder: recorder,
            heartRateMonitor: monitor
        )

        viewModel.start(modelContext: ModelContext(container))
        client.emit(.connected(id: deviceID, name: "Test Strap"))
        client.emit(
            .measurement(
                HeartRateMeasurement(beatsPerMinute: 138, sensorContact: .detected, receivedAt: readAt)
            )
        )
        await settle()
        viewModel.recordHeartRateSampleForSessionTick(at: readAt)

        #expect(viewModel.heartRateWorkoutSummary.timeSeries?.map(\.heartRate) == [138])

        client.emit(.disconnected(id: deviceID, wasRequested: false))
        await settle()
        viewModel.recordHeartRateSampleForSessionTick(at: readAt.addingTimeInterval(1))
        viewModel.recordHeartRateSampleForSessionTick(at: readAt.addingTimeInterval(2))

        #expect(viewModel.heartRateWorkoutSummary.timeSeries?.map(\.heartRate) == [138])
        #expect(monitor.connectionState == .reconnecting)
        #expect(viewModel.liveHeartRateStatus == .reconnecting)
        #expect(viewModel.isRecording)
        #expect(motionSession.startRecordingCallCount == 1)
    }

    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    @Test("An out-of-range reading reaches no consumer and leaves the last real reading standing")
    func implausibleReadingIsDiscardedAtTheSensorSeam() async throws {
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
            connectionSleep: { _ in }
        )
        let recorder = LiveHeartRateRecorder(sources: [service], minimumSampleInterval: 0)

        service.autoConnectIfRemembered()
        client.emit(.connected(id: deviceID, name: "Test Strap"))
        let lastRealReading = HeartRateMeasurement(
            beatsPerMinute: 141,
            sensorContact: .detected,
            receivedAt: Date()
        )
        client.emit(.measurement(lastRealReading))
        await settle()
        recorder.recordSample()

        for artifact in [512, 0] {
            client.emit(
                .measurement(
                    HeartRateMeasurement(
                        beatsPerMinute: artifact,
                        sensorContact: .detected,
                        receivedAt: Date()
                    )
                )
            )
        }
        await settle()

        #expect(service.currentMeasurement == lastRealReading)
        #expect(recorder.currentMeasurement == lastRealReading)
        #expect(recorder.samples.map(\.heartRate) == [141])
    }

    private func rememberDevice(id: UUID, in defaults: UserDefaults) {
        defaults.set(id.uuidString, forKey: "heartRateMonitor.rememberedDeviceID")
        defaults.set("Test Strap", forKey: "heartRateMonitor.rememberedDeviceName")
    }
}
