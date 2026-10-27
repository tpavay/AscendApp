import Foundation

final class CrashlyticsBreadcrumbSink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination> = [.crashlytics]

    private let reporter: any CrashlyticsReporting

    init(reporter: any CrashlyticsReporting) {
        self.reporter = reporter
    }

    func setCollectionEnabled(_ enabled: Bool) {}

    func setUserID(_ userID: String?) {}

    func record(_ record: EnvelopedTelemetryRecord) {
        reporter.addBreadcrumb(Self.breadcrumb(for: record))
    }

    /// A diagnostic record (`diagnostic:<name>`, from `AppDiagnosticsRecorder`) keeps the level
    /// it was recorded at, so Sentry's trail shows a refused checkpoint as an error and a memory
    /// warning as a warning; everything else is an ordinary info crumb.
    static func breadcrumb(for record: EnvelopedTelemetryRecord) -> TelemetryBreadcrumb {
        let isDiagnostic = record.name.hasPrefix("diagnostic:")
        let level: TelemetryBreadcrumb.Level
        if isDiagnostic, case .string(let rawLevel)? = record.parameters["diagnostic_level"],
           let parsed = TelemetryBreadcrumb.Level(rawValue: rawLevel) {
            level = parsed
        } else {
            level = .info
        }
        let data = isDiagnostic
            ? record.parameters.reduce(into: [String: String]()) { result, pair in
                guard pair.key != "diagnostic_id", pair.key != "diagnostic_level",
                      !TelemetryEnvelope.propertyKeys.contains(pair.key) else { return }
                result[pair.key] = pair.value.stringValue
            }
            : [:]
        return TelemetryBreadcrumb(
            category: isDiagnostic ? "ascend.diagnostic" : "ascend.telemetry",
            message: isDiagnostic ? record.crashlyticsMessage : record.crashlyticsMessage,
            level: level,
            data: data
        )
    }

    func record(screen: EnvelopedTelemetryScreen) {}
}
