import Foundation

/// Whether an app environment reports to Sentry at all.
///
/// Production only. All three environments used to report into the one
/// `ascend-ios` project, so the environments nobody is paged about set the noise
/// floor for the one that matters: over 30 days staging contributed 791 events
/// and dev 533, against production's 23 - production was 2% of the volume in its
/// own project. Dev builds run on the developer's own machine where the Xcode
/// console is the better tool, and staging failures are found by the person who
/// caused them, so neither starts the SDK.
///
/// Because this is the only gate, everything `SentryOptionsFactory` configures -
/// session replay included - is production-only by construction.
struct SentryReportingPolicy: Equatable {
    static let productionEnvironment = "production"

    let environment: String

    var startsSentry: Bool {
        environment == Self.productionEnvironment
    }

    init(environment: String) {
        self.environment = environment
    }

    init(buildMetadata: TelemetryBuildMetadata) {
        self.init(environment: buildMetadata.appEnvironment)
    }
}
