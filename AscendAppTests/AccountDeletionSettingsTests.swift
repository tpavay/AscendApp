import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AccountDeletionSettingsTests {
    @Test("Delete then re-sign-up in the same session starts with clean preferences", .bug(id: 389))
    func deleteThenResignupInSameSessionStartsClean() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        seedDeletedAccountsPreferences(settings: fixture.settings, defaults: fixture.defaults)
        fixture.cleanup.clearUserDefaults()

        assertFreshAccountPreferences(settings: fixture.settings, defaults: fixture.defaults)

        // The first write made by the replacement account must not resurrect values the deleted
        // account left in this process-wide singleton.
        fixture.settings.hasCompletedBaseLevelOnboarding = true
        #expect(fixture.defaults.string(forKey: "measurementSystem") == nil)
        #expect(fixture.defaults.object(forKey: "userFitnessLevel") == nil)
        #expect(fixture.defaults.object(forKey: "climbDropNotificationsEnabled.v1") == nil)
    }

    @Test("Delete then re-sign-up after relaunch starts with clean preferences", .bug(id: 389))
    func deleteThenResignupAfterRelaunchStartsClean() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        seedDeletedAccountsPreferences(settings: fixture.settings, defaults: fixture.defaults)
        fixture.cleanup.clearUserDefaults()

        let relaunchedSettings = SettingsManager(userDefaults: fixture.defaults)
        assertFreshAccountPreferences(settings: relaunchedSettings, defaults: fixture.defaults)
    }

    private func seedDeletedAccountsPreferences(
        settings: SettingsManager,
        defaults: UserDefaults
    ) {
        settings.measurementSystem = .metric
        settings.stepHeight = 21
        settings.fitnessLevel = .advanced
        settings.seededBaseLevel = 12
        settings.autoCalculatedBaseLevel = 14
        settings.manualBaseLevelOverride = 16
        settings.hasCompletedBaseLevelOnboarding = true
        settings.fitnessLevel = .advanced
        defaults.set(true, forKey: "climbDropNotificationsEnabled.v1")
    }

    private func assertFreshAccountPreferences(
        settings: SettingsManager,
        defaults: UserDefaults,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(settings.measurementSystem == .imperial, sourceLocation: sourceLocation)
        #expect(
            settings.stepHeight == MeasurementSystem.imperial.defaultStepHeight,
            sourceLocation: sourceLocation
        )
        #expect(settings.fitnessLevel == .intermediate, sourceLocation: sourceLocation)
        #expect(settings.seededBaseLevel == 7, sourceLocation: sourceLocation)
        #expect(settings.autoCalculatedBaseLevel == nil, sourceLocation: sourceLocation)
        #expect(settings.manualBaseLevelOverride == nil, sourceLocation: sourceLocation)
        #expect(settings.hasCompletedBaseLevelOnboarding == false, sourceLocation: sourceLocation)
        #expect(settings.fitnessLevel == .intermediate, sourceLocation: sourceLocation)
        #expect(
            defaults.object(forKey: "climbDropNotificationsEnabled.v1") == nil,
            sourceLocation: sourceLocation
        )
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "AccountDeletionSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(userDefaults: defaults)
        let coordinator = AuthenticatedBootstrapCoordinator()
        let cleanup = AppAccountDeletionLocalCleanup(
            userDefaults: defaults,
            persistentDomainName: suiteName,
            settingsManager: settings,
            bootstrapCoordinator: coordinator
        )
        return Fixture(
            suiteName: suiteName,
            defaults: defaults,
            settings: settings,
            cleanup: cleanup
        )
    }

    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let settings: SettingsManager
        let cleanup: AppAccountDeletionLocalCleanup
    }
}
