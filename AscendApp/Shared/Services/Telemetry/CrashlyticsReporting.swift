import Foundation

protocol CrashlyticsReporting: Sendable {
    func setCollectionEnabled(_ enabled: Bool)
    func setUserID(_ userID: String?)
    func setCustomValue(_ value: Bool, forKey key: String)
    func setCustomValue(_ value: Int, forKey key: String)
    func setCustomValue(_ value: String, forKey key: String)
    func log(_ message: String)
    func addBreadcrumb(_ breadcrumb: TelemetryBreadcrumb)
    func record(
        error: Error,
        context: String,
        code: String,
        additionalInfo: [String: String]?,
        severity: TelemetryErrorSeverity
    )
    /// A fact worth an issue of its own that is not an error thrown in this process - a crash
    /// diagnostic the system handed over about the previous one. The text is the event, so it
    /// has to reach the reporter whole and searchable, which a breadcrumb's bounded data cannot
    /// promise and a synthetic `Error`'s domain and code would bury.
    func record(
        message: String,
        code: String,
        additionalInfo: [String: String]?,
        severity: TelemetryErrorSeverity
    )
}

extension CrashlyticsReporting {
    /// A reporter with no leveled trail of its own keeps the breadcrumb as a log line.
    func addBreadcrumb(_ breadcrumb: TelemetryBreadcrumb) {
        log(breadcrumb.logLine)
    }

    /// A reporter with no message event of its own keeps the message as a log line.
    func record(
        message: String,
        code: String,
        additionalInfo: [String: String]?,
        severity: TelemetryErrorSeverity
    ) {
        log("[\(severity.rawValue)] \(code): \(message)")
    }
}
