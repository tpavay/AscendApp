import Foundation
import FirebaseRemoteConfig

/// Reads ``RemoteConfigSetting`` values.
///
/// Deliberately narrow and separate from the kill-switch pipeline, which is Boolean end to end
/// (`RemoteFeatureFlagSource` answers `[String: Bool]`). Widening that pipeline to carry numbers
/// would put every kill switch's resolution path at risk for the sake of one setting; a switch
/// that fails to resolve disables a data path nobody chose to disable, and that trade is not worth
/// making.
protocol RemoteConfigSettingReading: Sendable {
    func integer(_ setting: RemoteConfigSetting) -> Int
}

struct FirebaseRemoteConfigSettingReader: RemoteConfigSettingReading {
    func integer(_ setting: RemoteConfigSetting) -> Int {
        let configValue = RemoteConfig.remoteConfig().configValue(forKey: setting.rawValue)

        // "The server said N" and "nobody has answered yet" are different answers, and only
        // `source == .remote` tells them apart - the same thing
        // `FirebaseRemoteFeatureFlagSource.remoteSourcedValues()` requires. The app deliberately
        // calls no `setDefaults`, so an unfetched key resolves to 0 through `numberValue`; reading
        // that as an answer would make every launch record `build|0` before the fetch and
        // `build|N` after it, flapping the recovery basis and spending the one re-open attempt on
        // essentially every launch.
        guard configValue.source == .remote else { return setting.shippedDefault }

        return configValue.numberValue.intValue
    }
}
