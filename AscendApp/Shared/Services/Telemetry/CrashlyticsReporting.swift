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
}

extension CrashlyticsReporting {
    /// A reporter with no leveled trail of its own keeps the breadcrumb as a log line.
    func addBreadcrumb(_ breadcrumb: TelemetryBreadcrumb) {
        log(breadcrumb.logLine)
    }
}
