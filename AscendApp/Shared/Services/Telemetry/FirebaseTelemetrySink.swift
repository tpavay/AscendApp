import FirebaseAnalytics
import Foundation

final class FirebaseTelemetrySink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination> = [.analytics]

    func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    func setUserID(_ userID: String?) {
        Analytics.setUserID(userID)
    }

    func record(_ record: TelemetryRecord) {
        Analytics.logEvent(record.name, parameters: record.firebaseParameters)
    }

    func record(screen: TelemetryScreen) {
        var parameters = screen.firebaseParameters
        parameters[AnalyticsParameterScreenName] = screen.name
        parameters[AnalyticsParameterScreenClass] = screen.screenClass
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
    }
}

private extension Dictionary where Key == String, Value == TelemetryValue {
    var firebaseParameters: [String: Any] {
        reduce(into: [String: Any]()) { partialResult, entry in
            partialResult[entry.key] = entry.value.firebaseValue
        }
    }
}

private extension TelemetryScreen {
    var firebaseParameters: [String: Any] {
        parameters.firebaseParameters
    }
}

private extension TelemetryRecord {
    var firebaseParameters: [String: Any] {
        parameters.firebaseParameters
    }
}
