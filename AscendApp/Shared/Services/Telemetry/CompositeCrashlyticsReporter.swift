import Foundation

final class CompositeCrashlyticsReporter: CrashlyticsReporting, @unchecked Sendable {
    private let reporters: [any CrashlyticsReporting]

    init(reporters: [any CrashlyticsReporting]) {
        self.reporters = reporters
    }

    func setCollectionEnabled(_ enabled: Bool) {
        reporters.forEach { $0.setCollectionEnabled(enabled) }
    }

    func setUserID(_ userID: String?) {
        reporters.forEach { $0.setUserID(userID) }
    }

    func setCustomValue(_ value: Bool, forKey key: String) {
        reporters.forEach { $0.setCustomValue(value, forKey: key) }
    }

    func setCustomValue(_ value: Int, forKey key: String) {
        reporters.forEach { $0.setCustomValue(value, forKey: key) }
    }

    func setCustomValue(_ value: String, forKey key: String) {
        reporters.forEach { $0.setCustomValue(value, forKey: key) }
    }

    func log(_ message: String) {
        reporters.forEach { $0.log(message) }
    }

    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {
        reporters.forEach {
            $0.record(
                error: error,
                context: context,
                code: code,
                additionalInfo: additionalInfo
            )
        }
    }
}
