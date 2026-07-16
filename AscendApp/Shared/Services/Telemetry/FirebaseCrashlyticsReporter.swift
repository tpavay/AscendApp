import FirebaseCrashlytics
import Foundation

final class FirebaseCrashlyticsReporter: CrashlyticsReporting, @unchecked Sendable {
    func setCollectionEnabled(_ enabled: Bool) {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    func setUserID(_ userID: String?) {
        Crashlytics.crashlytics().setUserID(userID ?? "")
    }

    func setCustomValue(_ value: Bool, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func setCustomValue(_ value: Int, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func setCustomValue(_ value: String, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {
        var userInfo: [String: Any] = [
            "context": context,
            "error_code": code
        ]

        if let additionalInfo {
            for (key, value) in additionalInfo {
                userInfo[key] = value
            }
        }

        Crashlytics.crashlytics().record(error: error, userInfo: userInfo)
    }
}
