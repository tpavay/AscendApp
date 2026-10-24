import Foundation
@preconcurrency import Sentry

final class SentryDiagnosticsReporter: CrashlyticsReporting, @unchecked Sendable {
    private let configuration: SentryConfiguration
    private let buildMetadata: TelemetryBuildMetadata
    private let floodGuard: SentryEventFloodGuard
    private let lock = NSLock()
    private var didStart = false

    init(
        configuration: SentryConfiguration = .live,
        buildMetadata: TelemetryBuildMetadata = .current,
        floodGuard: SentryEventFloodGuard = SentryEventFloodGuard()
    ) {
        self.configuration = configuration
        self.buildMetadata = buildMetadata
        self.floodGuard = floodGuard
    }

    func setCollectionEnabled(_ enabled: Bool) {
        guard enabled,
              let options = SentryOptionsFactory.makeOptions(
                  configuration: configuration,
                  buildMetadata: buildMetadata,
                  floodGuard: floodGuard
              )
        else {
            closeIfNeeded()
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard !didStart else { return }

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
        addBreadcrumb(TelemetryBreadcrumb(category: "ascend.telemetry", message: message, level: .info))
    }

    func addBreadcrumb(_ breadcrumb: TelemetryBreadcrumb) {
        guard didStart else { return }

        let sentryBreadcrumb = Breadcrumb(level: breadcrumb.level.sentryLevel, category: breadcrumb.category)
        sentryBreadcrumb.message = breadcrumb.message
        sentryBreadcrumb.type = "default"
        if !breadcrumb.data.isEmpty {
            sentryBreadcrumb.data = breadcrumb.data
        }
        SentrySDK.addBreadcrumb(sentryBreadcrumb)
    }

    func record(
        error: Error,
        context: String,
        code: String,
        additionalInfo: [String: String]?,
        severity: TelemetryErrorSeverity
    ) {
        guard didStart else { return }

        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "ascend_error_context")
            scope.setTag(value: code, key: "ascend_error_code")
            scope.setLevel(severity.sentryLevel)

            if let additionalInfo, !additionalInfo.isEmpty {
                scope.setContext(value: additionalInfo, key: "ascend")
            }
        }
    }

    /// A message event, not an error event: Sentry groups it by its text, so every distinct
    /// assertion string becomes its own issue and the text itself is what `message:` search
    /// finds. Never fatal - it describes a crash that already happened, and a fatal level
    /// would make `SentryEventClassification` bypass the flood guard and take a screenshot of a
    /// launch that has nothing to do with it.
    func record(
        message: String,
        code: String,
        additionalInfo: [String: String]?,
        severity: TelemetryErrorSeverity
    ) {
        guard didStart else { return }

        SentrySDK.capture(message: message) { scope in
            scope.setTag(value: code, key: "ascend_error_code")
            scope.setLevel(severity.sentryLevel)

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

private extension TelemetryErrorSeverity {
    var sentryLevel: SentryLevel {
        switch self {
        case .warning: .warning
        case .error: .error
        }
    }
}

private extension TelemetryBreadcrumb.Level {
    var sentryLevel: SentryLevel {
        switch self {
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}
