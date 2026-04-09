import Foundation

final class CrashlyticsBreadcrumbSink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination> = [.crashlytics]

    private let reporter: any CrashlyticsReporting

    init(reporter: any CrashlyticsReporting) {
        self.reporter = reporter
    }

    func setCollectionEnabled(_ enabled: Bool) {}

    func setUserID(_ userID: String?) {}

    func record(_ record: TelemetryRecord) {
        reporter.log(record.crashlyticsMessage)
    }

    func record(screen: TelemetryScreen) {}
}
