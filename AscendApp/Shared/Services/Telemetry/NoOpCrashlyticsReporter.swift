import Foundation

final class NoOpCrashlyticsReporter: CrashlyticsReporting, @unchecked Sendable {
    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}
