import Foundation
@preconcurrency import Sentry

final class SentryDiagnosticsReporter: CrashlyticsReporting, @unchecked Sendable {
    private let configuration: SentryConfiguration
    private let lock = NSLock()
    private var didStart = false

    init(configuration: SentryConfiguration = .live) {
        self.configuration = configuration
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
        options.environment = Self.appEnvironmentName
        options.releaseName = Self.releaseName
        options.dist = Self.buildNumber
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
            scope.setTag(value: Self.appEnvironmentName, key: "app_environment")
            scope.setTag(value: Self.buildConfigName, key: "build_config")
            scope.setTag(value: Self.appVersion, key: "app_version")
            scope.setTag(value: Self.buildNumber, key: "build_number")
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

    private static var appEnvironmentName: String {
        #if DEBUG
        return "dev"
        #elseif STAGING
        return "staging"
        #else
        return "production"
        #endif
    }

    private static var buildConfigName: String {
        #if DEBUG
        return "debug"
        #elseif STAGING
        return "staging"
        #else
        return "release"
        #endif
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    private static var releaseName: String {
        "\(Bundle.main.bundleIdentifier ?? "AscendApp")@\(appVersion)+\(buildNumber)"
    }
}
