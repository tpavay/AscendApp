import Foundation
import Testing
@testable import AscendApp

/// The Mixpanel identity is only ever cleared on a real signed-in -> signed-out transition.
///
/// `setUserID(nil)` reaches `MixpanelInstance.reset()`, which mints a brand new random device id.
/// Firebase's auth listener reports "no user" on every signed-out cold launch, so clearing on that
/// report severed 19 of 37 climbers from their own `app_first_opened` and welcome screen - the
/// entire 37 -> 9 cliff on the production onboarding board. Each test below is one of the four
/// launches the listener can produce.
struct TelemetryIdentityLifecycleTests {
    @Test("A cold launch with no session keeps one identity across first open and the first screen")
    func coldLaunchSignedOutNeverClearsAnIdentity() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink, identityStore: makeTestIdentityStore())

        telemetry.track(TelemetryRecord(name: "app_first_opened"))
        // The listener's first report on a launch nobody is signed in to.
        let didClear = telemetry.clearUserId()
        telemetry.track(TelemetryRecord(name: "onboarding_screen_viewed"))

        #expect(didClear == false)
        #expect(sink.userIDs.isEmpty)
        #expect(sink.records.map(\.name) == ["app_first_opened", "onboarding_screen_viewed"])
    }

    @Test("A cold launch that restores a session identifies without clearing first")
    func coldLaunchSignedInIdentifiesWithoutRotatingTheDeviceID() {
        let store = makeTestIdentityStore()
        let firstLaunchSink = InMemoryTelemetrySink(destination: .analytics)
        makeTestTelemetry(sink: firstLaunchSink, identityStore: store).setUserId("climber-a")

        let relaunchSink = InMemoryTelemetrySink(destination: .analytics)
        let relaunched = makeTestTelemetry(sink: relaunchSink, identityStore: store)
        relaunched.setUserId("climber-a")

        #expect(relaunchSink.userIDs == ["climber-a"])
    }

    @Test("Signing out during a session clears the identity exactly once")
    func signOutClearsTheIdentityAndSaysSo() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink, identityStore: makeTestIdentityStore())

        telemetry.setUserId("climber-a")
        let didClear = telemetry.clearUserId()
        // Firebase can report "no user" again before the next sign-in; the identity is already gone.
        let didClearAgain = telemetry.clearUserId()

        #expect(didClear)
        #expect(didClearAgain == false)
        #expect(sink.userIDs == ["climber-a", nil])
    }

    @Test("An account switch clears the departing climber before identifying the arriving one")
    func accountSwitchNeverMergesTwoClimbersIntoOneProfile() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink, identityStore: makeTestIdentityStore())

        telemetry.setUserId("climber-a")
        telemetry.setUserId("climber-b")

        // Without the clear in the middle, Mixpanel's `$identify` would carry climber-a's id as
        // `$anon_distinct_id` and merge the two people into one profile.
        #expect(sink.userIDs == ["climber-a", nil, "climber-b"])
    }

    @Test("A session revoked while the app was closed still counts as a sign-out on the next launch")
    func revokedSessionClearsOnTheNextColdLaunch() {
        let store = makeTestIdentityStore()
        makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics), identityStore: store)
            .setUserId("climber-a")

        let relaunchSink = InMemoryTelemetrySink(destination: .analytics)
        let relaunched = makeTestTelemetry(sink: relaunchSink, identityStore: store)
        let didClear = relaunched.clearUserId()

        // The identity outlived the process, so the launch that finds it gone is a real sign-out:
        // the departed account must stop collecting whatever the next anonymous session does.
        #expect(didClear)
        #expect(relaunchSink.userIDs == [nil])
    }

    /// Suppressed collection must not bank an identity the sinks never received, or the launch
    /// that turns collection on would report a sign-out for an account it never identified.
    @Test("Disabled collection stores no identity")
    func disabledCollectionRecordsNoIdentity() {
        let store = makeTestIdentityStore()
        let telemetry = makeTestTelemetry(
            sink: InMemoryTelemetrySink(destination: .analytics),
            collectionEnabled: false,
            identityStore: store
        )

        telemetry.setUserId("climber-a")

        #expect(store.identifiedUserID == nil)
        #expect(telemetry.clearUserId() == false)
    }
}

/// The shipped store is the half of the contract the in-memory double cannot prove: the record has
/// to outlive the process, or a session revoked while the app was closed would look exactly like a
/// launch nobody ever signed in to.
struct TelemetryIdentityStoreTests {
    @Test("A fresh installation has no identity, and a stored one survives into the next launch")
    func theStoredIdentityOutlivesTheProcessThatWroteIt() throws {
        let suiteName = "TelemetryIdentityStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(TelemetryIdentityStore(defaults: defaults).identifiedUserID == nil)

        TelemetryIdentityStore(defaults: defaults).store("climber-a")
        #expect(TelemetryIdentityStore(defaults: defaults).identifiedUserID == "climber-a")

        TelemetryIdentityStore(defaults: defaults).clear()
        #expect(TelemetryIdentityStore(defaults: defaults).identifiedUserID == nil)
    }

    /// Account deletion clears the app's own persistent domain wholesale while Mixpanel keeps its
    /// identity in a suite of its own, so a mirror that wipe could reach would leave the next
    /// anonymous session reporting as the deleted account.
    @Test("The identity record lives outside the domain account deletion clears")
    func theIdentityRecordSurvivesAnAccountPreferenceWipe() throws {
        let bundleIdentifier = "TelemetryIdentityStoreTests.\(UUID().uuidString)"
        let accountDefaults = try #require(UserDefaults(suiteName: bundleIdentifier))
        let installationDomain = "\(bundleIdentifier).installation"
        let installationDefaults = AppInstallationTelemetryReporter.installationDefaults(
            bundleIdentifier: bundleIdentifier
        )
        defer {
            accountDefaults.removePersistentDomain(forName: bundleIdentifier)
            installationDefaults.removePersistentDomain(forName: installationDomain)
        }

        TelemetryIdentityStore(defaults: installationDefaults).store("climber-a")
        accountDefaults.removePersistentDomain(forName: bundleIdentifier)

        let afterWipe = TelemetryIdentityStore(
            defaults: AppInstallationTelemetryReporter.installationDefaults(
                bundleIdentifier: bundleIdentifier
            )
        )
        #expect(afterWipe.identifiedUserID == "climber-a")
    }
}
