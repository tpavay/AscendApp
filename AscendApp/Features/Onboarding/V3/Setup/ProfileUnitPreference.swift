import Foundation

/// The unit the height and weight sheets open in: the phone's region until the climber changes it,
/// and what they chose from then on.
///
/// It is its own remembered choice, not `SettingsManager.measurementSystem`: onboarding runs before
/// an account exists and must not rewrite an app setting that converts stored step heights.
struct ProfileUnitPreference: @unchecked Sendable {
    static let storageKey = "onboarding.profileSetup.measurementSystem"

    private let userDefaults: UserDefaults
    private let regionDefault: MeasurementSystem

    init(
        userDefaults: UserDefaults = .standard,
        regionDefault: MeasurementSystem = Self.systemForCurrentRegion()
    ) {
        self.userDefaults = userDefaults
        self.regionDefault = regionDefault
    }

    var system: MeasurementSystem {
        userDefaults.string(forKey: Self.storageKey).flatMap(MeasurementSystem.init(rawValue:)) ?? regionDefault
    }

    func remember(_ system: MeasurementSystem) {
        userDefaults.set(system.rawValue, forKey: Self.storageKey)
    }

    /// Metric where the region measures in metric, imperial in the US and the UK.
    static func systemForCurrentRegion(_ locale: Locale = .current) -> MeasurementSystem {
        locale.measurementSystem == .metric ? .metric : .imperial
    }
}
