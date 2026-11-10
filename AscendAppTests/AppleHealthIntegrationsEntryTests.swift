import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Settings -> Integrations -> Apple Health -> Manage, the one place Settings keeps Apple Health:
/// the Import automatically switch, Import older workouts, and the gates each one sits behind.
/// `SettingsReorganizationEvidenceTests` holds Settings itself to carrying no Apple Health section.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppleHealthIntegrationsEntryTests {
    private static let size = CGSize(width: 402, height: 874)

    private func switchedOff(_ flag: RemoteFeatureFlag) -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(snapshot: RemoteFeatureFlagSnapshot.resolving(remoteValues: [flag.key: false]))
    }

    /// The sheet as the Apple Health card presents it.
    private func manageSheet(_ harness: AppleHealthImportHarness) -> some View {
        AppleHealthManageSheet(
            isPresented: .constant(true),
            importService: harness.service,
            onCheckNow: {},
            onOpenHealthPermissions: {}
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .modelContainer(harness.container)
    }

    // MARK: - The rows

    @Test("Connected: the Import automatically switch and Import older workouts, above the heart-rate rows")
    func connectedShowsTheImportRows() async throws {
        let harness = try AppleHealthImportHarness()

        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let copy = try await screen.copy { $0.contains("import older workouts") }
            #expect(copy.contains("apple health"), "\(copy)")
            #expect(copy.contains("import automatically"), "\(copy)")
            #expect(copy.contains(AppleHealthManageSheet.autoImportDetail.lowercased()), "\(copy)")
            #expect(copy.contains(AppleHealthManageSheet.olderWorkoutsDetail.lowercased()), "\(copy)")
            #expect(copy.contains("check for heart rate now"), "\(copy)")
            #expect(copy.contains("manage health permissions"), "\(copy)")
            try screen.photograph(named: "integrations-apple-health-manage-connected")

            let toggle = try #require(try await screen.frame(ofElementLabelled: "Import automatically"))
            let older = try #require(try await screen.frame(ofElementLabelled: "Import older workouts"))
            let check = try #require(try await screen.frame(ofElementLabelled: "Check for heart rate now"))
            #expect(toggle.maxY <= older.minY, "\(toggle) \(older)")
            #expect(older.maxY <= check.minY, "\(older) \(check)")
            #expect(older.height >= 44, "a full tap target: \(older)")
        }
    }

    @Test("Import automatically is the same setting Imports and the Connect flow keep")
    func theSwitchIsBoundToTheAutoImportSetting() async throws {
        let harness = try AppleHealthImportHarness()
        #expect(harness.service.isAutoImportEnabled)

        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Import automatically") == true } }
            let toggle = try #require(elements.first { $0.accessibilityLabel?.contains("Import automatically") == true })
            #expect(toggle.accessibilityValue == "1", "on, which is the default")

            #expect(toggle.accessibilityActivate())
            try await screen.settle()
            #expect(!harness.settings.isAutoImportEnabled(for: AppleHealthImportHarness.userID))
            #expect(!harness.service.isAutoImportEnabled)
        }

        // Set from somewhere else, the row shows it.
        await harness.service.setAutoImportEnabled(true)
        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Import automatically") == true } }
            let toggle = try #require(elements.first { $0.accessibilityLabel?.contains("Import automatically") == true })
            #expect(toggle.accessibilityValue == "1")
        }
    }

    // MARK: - The gates

    @Test("The import kill switch off: the heart-rate rows stay and nothing about import shows")
    func theKillSwitchRemovesTheImportRows() async throws {
        let harness = try AppleHealthImportHarness(featureFlags: switchedOff(.appleHealthImport))

        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let copy = try await screen.copy { $0.contains("check for heart rate now") }
            #expect(copy.contains("manage health permissions"), "\(copy)")
            #expect(!copy.contains("import"), "\(copy)")
            try screen.photograph(named: "integrations-apple-health-manage-import-off")
        }
    }

    @Test("Health not connected for import: nothing imports, so no import rows")
    func notConnectedForImportShowsNoImportRows() async throws {
        let harness = try AppleHealthImportHarness()
        harness.authorization.importConnectionState = .neverConnected

        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let copy = try await screen.copy { $0.contains("check for heart rate now") }
            #expect(!copy.contains("import"), "\(copy)")
        }
    }

    @Test("A device with no Health: no import rows")
    func noHealthShowsNoImportRows() async throws {
        let harness = try AppleHealthImportHarness()
        harness.reader.isHealthDataAvailable = false

        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let copy = try await screen.copy { $0.contains("check for heart rate now") }
            #expect(!copy.contains("import"), "\(copy)")
        }
    }

    @Test("The history switch off: the switch stays, with no Import older workouts")
    func theHistorySwitchRemovesOnlyTheOlderWorkoutsRow() async throws {
        let harness = try AppleHealthImportHarness(featureFlags: switchedOff(.appleHealthHistoryImport))

        try await RenderedScreen.host(manageSheet(harness), size: Self.size) { screen in
            let copy = try await screen.copy { $0.contains("import automatically") }
            #expect(copy.contains(AppleHealthManageSheet.autoImportDetail.lowercased()), "\(copy)")
            #expect(!copy.contains("import older workouts"), "\(copy)")
        }
    }

    // MARK: - Import older workouts

    @Test("Import older workouts opens the same history screen as 07a, in the Connect flow's chrome")
    func importOlderWorkoutsOpensTheHistoryScreen() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40)
        harness.addWorkout(daysAgo: 400, steps: nil, minutes: 50, windowSteps: 5_000)

        try await RenderedScreen.host(manageSheet(harness), size: Self.size, settle: .turns(40)) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Import older workouts") == true } }
            let row = try #require(elements.first { $0.accessibilityLabel?.contains("Import older workouts") == true })
            #expect(row.accessibilityTraits.contains(.button))
            #expect(row.accessibilityActivate())

            let copy = try await screen.copy { $0.contains("to my history") }
            #expect(copy.contains("we found your climbs"), "\(copy)")
            #expect(copy.contains("8,000"), "the total counts the steps Health holds over a workout's window: \(copy)")
            #expect(copy.contains("steps in 2 stair stepper workouts"), "\(copy)")
            #expect(copy.contains("time range, everything since"), "\(copy)")
            #expect(copy.contains("add 2 to my history"), "\(copy)")
            #expect(copy.contains("not now"), "\(copy)")
            #expect(copy.contains(AppleHealthOlderWorkoutsView.footnote.lowercased()), "\(copy)")
            #expect(copy.contains("close"), "the flow's close X: \(copy)")
            #expect(!copy.contains("skip history"), "that is onboarding's link: \(copy)")
            #expect(!copy.contains("onboarding progress"), "\(copy)")
        }
    }
}
