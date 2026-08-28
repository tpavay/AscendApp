import Foundation

/// The account identity the app last handed to its telemetry sinks, remembered across launches.
///
/// This exists because clearing an identity is not free. `MixpanelInstance.reset()` mints a brand
/// new random device id, so calling it when there is no identity to clear does not "start clean" -
/// it discards the anonymous identity that `app_first_opened`, `onboarding_flow_started`, and the
/// welcome screen were recorded under, and Mixpanel's ID merge can never rejoin the two halves
/// because the discarded id never identifies. Firebase reports "no user" on every signed-out cold
/// launch, not only on a sign-out, which is the same distinction `MonetizationManager` already
/// draws for the onboarding pass (`ascend-analytics`, "Losing the authenticated identity is not a
/// sign-out"); telemetry had not been told.
///
/// The record has to survive relaunch, because a session revoked while the app was closed reports
/// its `nil` on the next cold launch with nothing in memory to compare against - and that one *is*
/// a sign-out, whose events must stop being attributed to the departed account.
protocol TelemetryIdentityStoring: AnyObject, Sendable {
    var identifiedUserID: String? { get }
    func store(_ userID: String)
    func clear()
}

/// The shipped store.
///
/// It lives in the installation-scoped suite for the same reason `app_first_opened`'s sentinel
/// does: account deletion clears the app's own persistent domain wholesale, while Mixpanel keeps
/// its identity in a suite of its own (`Mixpanel`) that the wipe never reaches. A mirror the wipe
/// could clear would leave the next anonymous session reporting as the deleted account.
final class TelemetryIdentityStore: TelemetryIdentityStoring, @unchecked Sendable {
    static let live = TelemetryIdentityStore()

    private static let identifiedUserIDKey = "telemetry.identifiedUserID.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppInstallationTelemetryReporter.installationDefaults()) {
        self.defaults = defaults
    }

    var identifiedUserID: String? {
        defaults.string(forKey: Self.identifiedUserIDKey)
    }

    func store(_ userID: String) {
        defaults.set(userID, forKey: Self.identifiedUserIDKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.identifiedUserIDKey)
    }
}
