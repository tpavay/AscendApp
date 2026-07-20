import Foundation

enum LiveHeartRateStatus: Equatable {
    case connecting
    case connected(beatsPerMinute: Int, zone: HeartRateZone)
    case signalLost
    case failed

    static func resolve(
        hasRememberedDevice: Bool,
        connectionState: HeartRateMonitorService.ConnectionState,
        freshMeasurement: HeartRateMeasurement?,
        zoneProfile: HeartRateZoneProfile
    ) -> LiveHeartRateStatus? {
        guard hasRememberedDevice else { return nil }

        switch connectionState {
        case .connecting, .scanning:
            return .connecting
        case .connected:
            guard let freshMeasurement else { return .signalLost }
            return .connected(
                beatsPerMinute: freshMeasurement.beatsPerMinute,
                zone: zoneProfile.zone(forBeatsPerMinute: freshMeasurement.beatsPerMinute)
            )
        case .disconnected, .failed:
            return .failed
        }
    }

    var displayText: String {
        switch self {
        case .connecting:
            return "Connecting strap"
        case .connected(let beatsPerMinute, _):
            return String(beatsPerMinute)
        case .signalLost:
            return "Signal lost"
        case .failed:
            return "No heart rate"
        }
    }

    var accessibilityText: String {
        switch self {
        case .connecting:
            return "Heart rate monitor connecting"
        case .connected(let beatsPerMinute, _):
            return "Heart rate \(beatsPerMinute) beats per minute"
        case .signalLost:
            return "Heart rate signal lost"
        case .failed:
            return "Heart rate unavailable"
        }
    }
}
