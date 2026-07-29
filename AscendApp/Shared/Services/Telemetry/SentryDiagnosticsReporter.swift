import Foundation
@preconcurrency import Sentry

final class SentryDiagnosticsReporter: CrashlyticsReporting, @unchecked Sendable {
    private let configuration: SentryConfiguration
    private let buildMetadata: TelemetryBuildMetadata
    private let lock = NSLock()
    private var didStart = false

    init(
        configuration: SentryConfiguration = .live,
        buildMetadata: TelemetryBuildMetadata = .current
    ) {
        self.configuration = configuration
        self.buildMetadata = buildMetadata
    }

    func setCollectionEnabled(_ enabled: Bool) {
        guard enabled, configuration.canConfigure, let dsn = configuration.dsn else {
            closeIfNeeded()
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard !didStart else { return }

        let options = Options()
        options.dsn = dsn
        options.environment = buildMetadata.appEnvironment
        options.releaseName = buildMetadata.releaseName
        options.dist = buildMetadata.buildNumber
        options.sendDefaultPii = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enableUserInteractionTracing = false
        options.enableFileIOTracing = false

        #if DEBUG
        options.debug = true
        #endif

        SentrySDK.start(options: options)
        SentrySDK.configureScope { scope in
            self.buildMetadata.properties.forEach { key, value in
                scope.setTag(value: value, key: key)
            }
        }
        didStart = true
    }

    func setUserID(_ userID: String?) {
        guard didStart else { return }

        if let userID {
            SentrySDK.setUser(User(userId: userID))
        } else {
            SentrySDK.setUser(nil)
        }
    }

    func setCustomValue(_ value: Bool, forKey key: String) {
        setCustomValue(value ? "true" : "false", forKey: key)
    }

    func setCustomValue(_ value: Int, forKey key: String) {
        setCustomValue(String(value), forKey: key)
    }

    func setCustomValue(_ value: String, forKey key: String) {
        guard didStart else { return }

        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
    }

    func log(_ message: String) {
        guard didStart else { return }

        let breadcrumb = Breadcrumb(level: .info, category: "ascend.telemetry")
        breadcrumb.message = message
        breadcrumb.type = "default"
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {
        guard didStart else { return }

        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "ascend_error_context")
            scope.setTag(value: code, key: "ascend_error_code")

            if let additionalInfo, !additionalInfo.isEmpty {
                scope.setContext(value: additionalInfo, key: "ascend")
            }
        }
    }

    private func closeIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard didStart else { return }
        SentrySDK.close()
        didStart = false
    }
}
