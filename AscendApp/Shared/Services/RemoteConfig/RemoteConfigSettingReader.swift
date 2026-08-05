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
        let value = RemoteConfig.remoteConfig()[setting.rawValue].numberValue.intValue
        // A device that has never fetched reads the shipped default, and the shipped default
        // equals the template's baseline. That equality is load-bearing: if they differed, the
        // first successful fetch would look like an operator bump and re-open the whole fleet.
        return value
    }
}
