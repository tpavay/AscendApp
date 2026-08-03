import Foundation
import Testing
@testable import AscendApp

struct LiveHeartRateStatusTests {
    private let zoneProfile = HeartRateZoneProfile(age: 30)

    @Test("Live UI status matches monitor state and sample freshness")
    func resolvesEveryRenderedState() {
        let measurement = HeartRateMeasurement(
            beatsPerMinute: 150,
            sensorContact: .detected,
            receivedAt: Date()
        )

        #expect(resolve(connectionState: .connecting) == .connecting)
        #expect(
            resolve(connectionState: .connected, measurement: measurement)
                == .connected(beatsPerMinute: 150, zone: .aerobic)
        )
        #expect(resolve(connectionState: .connected) == .signalLost)
        #expect(resolve(connectionState: .reconnecting) == .reconnecting)
        #expect(resolve(connectionState: .failed) == .failed)
    }

    @Test("Live UI copy stays calm and explicit")
    func displayCopy() {
        #expect(LiveHeartRateStatus.connecting.displayText == "Connecting strap")
        #expect(LiveHeartRateStatus.reconnecting.displayText == "Reconnecting")
        #expect(LiveHeartRateStatus.signalLost.displayText == "Signal lost")
        #expect(LiveHeartRateStatus.failed.displayText == "No heart rate")
        #expect(
            LiveHeartRateStatus.connected(beatsPerMinute: 148, zone: .aerobic).displayText
                == "148"
        )
    }

    private func resolve(
        connectionState: HeartRateMonitorService.ConnectionState,
        measurement: HeartRateMeasurement? = nil
    ) -> LiveHeartRateStatus? {
        LiveHeartRateStatus.resolve(
            hasRememberedDevice: true,
            connectionState: connectionState,
            freshMeasurement: measurement,
            zoneProfile: zoneProfile
        )
    }
}
