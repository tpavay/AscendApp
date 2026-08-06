import Foundation

/// Remote Config parameters that carry a value an operator moves, rather than a path they switch
/// off.
///
/// Deliberately separate from ``RemoteFeatureFlag``: a kill switch is a Boolean that ships on and
/// is flipped off to stop something, and treating a setting as one would mean the healthy state was
/// a lie. `scripts/lib/remote-config-template.mjs` holds both to their own contract and still
/// requires every parameter to be read by a case here or there, because a parameter nothing reads
/// is a lever that moves nothing.
///
/// Each case's raw value is the Remote Config parameter key.
enum RemoteConfigSetting: String, CaseIterable, Sendable {
    /// The operator-controlled recovery epoch.
    ///
    /// Bumping it after a rules or backend fix gives every workout whose automatic sync series has
    /// stopped exactly one more attempt, across the whole fleet, without shipping a binary. That
    /// is not a nicety: `firestore.rules` deploys independently of app releases, so a build-change
    /// trigger on its own cannot unstick the workouts a rules fix repairs - including the ones
    /// this very change repairs.
    ///
    /// Only ever increase it. It is compared for difference, not magnitude, but decreasing it
    /// would re-open on the way back down for no stated reason.
    case workoutSyncRecoveryEpoch = "workout_sync_recovery_epoch"

    /// What the app falls back to when Remote Config has never answered for this key.
    ///
    /// Zero, and it matters that it is: a device that has not fetched must look identical to one
    /// that fetched the baseline, or the first successful fetch would read as a bump and re-open
    /// the fleet for no reason. `FirebaseRemoteConfigSettingReader` returns this whenever the
    /// resolved value's source is not `.remote`, so an unfetched key can never be mistaken for an
    /// operator's answer.
    var shippedDefault: Int {
        switch self {
        case .workoutSyncRecoveryEpoch:
            return 0
        }
    }
}
