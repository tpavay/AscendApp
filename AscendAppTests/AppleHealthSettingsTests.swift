import Foundation
import HealthKit
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Settings -> Apple Health: the three rows, what each one does, and Import older workouts, which
/// is onboarding's "We found your climbs" for a climber who already has an account.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppleHealthSettingsTests {
    private func switchedOff(_ flag: RemoteFeatureFlag) -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(snapshot: RemoteFeatureFlagSnapshot.resolving(remoteValues: [flag.key: false]))
    }

    /// The screen as Settings pushes it.
    private func section(
        _ harness: AppleHealthImportHarness,
        openHealthApp: @escaping () -> Void = {}
    ) -> some View {
        NavigationStack {
            AppleHealthSettingsView(importService: harness.service, openHealthApp: openHealthApp)
        }
        .preferredColorScheme(.dark)
        .modelContainer(harness.container)
    }

    // MARK: - The rows

    @Test("Off: one row that says so and opens the Connect flow")
    func offShowsOneRowThatOpensTheConnectFlow() async throws {
        let harness = try AppleHealthImportHarness()
        harness.authorization.importConnectionState = .neverConnected

        try await RenderedScreen.host(section(harness), size: CGSize(width: 402, height: 874)) { screen in
            let copy = try await screen.copy { $0.contains("off. connect") }
            #expect(copy.contains("apple health"), "\(copy)")
            #expect(copy.contains(AppleHealthSettingsView.offDetail.lowercased()), "\(copy)")
            #expect(!copy.contains("import automatically"), "nothing imports until Health is connected: \(copy)")
            #expect(!copy.contains("import older workouts"), "\(copy)")
            try screen.photograph(named: "settings-apple-health-off")

            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Off. Connect") == true } }
            let row = try #require(elements.first { $0.accessibilityLabel?.contains("Off. Connect") == true })
            #expect(row.accessibilityTraits.contains(.button))
            #expect(row.accessibilityActivate())
            let flow = try await screen.copy { $0.contains("connect apple health") }
            #expect(flow.contains("counted for you."), "the existing Connect flow: \(flow)")
        }
    }

    @Test("Connected: the status row, the Import automatically switch, and Import older workouts")
    func connectedShowsTheThreeRows() async throws {
        let harness = try AppleHealthImportHarness()
        var healthAppOpens = 0

        try await RenderedScreen.host(
            section(harness, openHealthApp: { healthAppOpens += 1 }),
            size: CGSize(width: 402, height: 874)
        ) { screen in
            let copy = try await screen.copy { $0.contains("import older workouts") }
            #expect(copy.contains("apple health"), "\(copy)")
            #expect(copy.contains(AppleHealthSettingsView.connectedDetail.lowercased()), "\(copy)")
            #expect(copy.contains("import automatically"), "\(copy)")
            #expect(copy.contains(AppleHealthSettingsView.autoImportDetail.lowercased()), "\(copy)")
            #expect(copy.contains(AppleHealthSettingsView.olderWorkoutsDetail.lowercased()), "\(copy)")
            #expect(!copy.contains("off. connect"), "\(copy)")
            try screen.photograph(named: "settings-apple-health-connected")

            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Manage access") == true } }
            let status = try #require(elements.first { $0.accessibilityLabel?.contains("Manage access") == true })
            #expect(status.accessibilityActivate())
            #expect(healthAppOpens == 1, "access is managed in the Health app, so the row goes there")
        }
    }

    @Test("Import automatically is the same setting Imports and the Connect flow keep")
    func theSwitchIsBoundToTheAutoImportSetting() async throws {
        let harness = try AppleHealthImportHarness()
        #expect(harness.service.isAutoImportEnabled)

        try await RenderedScreen.host(section(harness), size: CGSize(width: 402, height: 874)) { screen in
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
        try await RenderedScreen.host(section(harness), size: CGSize(width: 402, height: 874)) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Import automatically") == true } }
            let toggle = try #require(elements.first { $0.accessibilityLabel?.contains("Import automatically") == true })
            #expect(toggle.accessibilityValue == "1")
        }
    }

    @Test("The import kill switch off: Settings shows no row, and the screen offers nothing")
    func theKillSwitchRemovesTheRows() async throws {
        let harness = try AppleHealthImportHarness(featureFlags: switchedOff(.appleHealthImport))
        #expect(!AppleHealthSettingsView.isOffered(by: harness.service), "Settings draws no row to this screen")

        try await RenderedScreen.host(section(harness), size: CGSize(width: 402, height: 874)) { screen in
            let copy = try await screen.copy { $0.contains("not available") }
            #expect(copy.contains(AppleHealthSettingsView.notOfferedDetail.lowercased()), "\(copy)")
            #expect(!copy.contains("import automatically"), "\(copy)")
            #expect(!copy.contains("connect to import"), "\(copy)")
        }
    }

    @Test("Settings shows the row when import is on offer, connected or not, and not on a device with no Health")
    func settingsOffersTheRowOnlyWhereImportIsOnOffer() throws {
        let connected = try AppleHealthImportHarness()
        #expect(AppleHealthSettingsView.isOffered(by: connected.service))

        let never = try AppleHealthImportHarness()
        never.authorization.importConnectionState = .neverConnected
        #expect(AppleHealthSettingsView.isOffered(by: never.service))

        let noHealth = try AppleHealthImportHarness()
        noHealth.reader.isHealthDataAvailable = false
        #expect(!AppleHealthSettingsView.isOffered(by: noHealth.service))
    }

    @Test("The history switch off: connected, with no Import older workouts")
    func theHistorySwitchRemovesOnlyTheOlderWorkoutsRow() async throws {
        let harness = try AppleHealthImportHarness(featureFlags: switchedOff(.appleHealthHistoryImport))

        try await RenderedScreen.host(section(harness), size: CGSize(width: 402, height: 874)) { screen in
            let copy = try await screen.copy { $0.contains("import automatically") }
            #expect(copy.contains(AppleHealthSettingsView.connectedDetail.lowercased()), "\(copy)")
            #expect(!copy.contains("import older workouts"), "\(copy)")
        }
    }

    /// Settings rows carry a chevron and no state (`SettingsReorganizationEvidenceTests`), so the
    /// three rows live one screen in and Settings has a single plain row to it. Settings reads the
    /// process-wide service, whose Health availability belongs to the simulator, so the row is
    /// held to whatever that service says is on offer.
    @Test("Settings carries one plain row to the screen, between Preferences and Purchases")
    func settingsCarriesOnePlainRowToTheScreen() async throws {
        UserDefaults.standard.set("Maya Chen", forKey: "displayName")
        let settings = NavigationStack {
            AccountView()
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
        }
        .preferredColorScheme(.dark)
        let isOffered = AppleHealthSettingsView.isOffered(by: .shared)

        try await RenderedScreen.host(settings, size: CGSize(width: 390, height: 1500)) { screen in
            let copy = try await screen.copy { $0.contains("purchases") }
            let words = Set(copy.split(whereSeparator: { !$0.isLetter }).map(String.init))
            #expect(!words.contains("on"), "a Settings row is summarising its state as On: \(copy)")
            #expect(!words.contains("off"), "a Settings row is summarising its state as Off: \(copy)")

            guard isOffered else {
                #expect(!copy.contains("apple health"), "\(copy)")
                #expect(!copy.contains("workout import"), "\(copy)")
                return
            }

            var searchStart = copy.startIndex
            var headers: [Range<String.Index>] = []
            for header in ["profile", "notifications", "preferences", "apple health", "purchases"] {
                let range = try #require(
                    copy.range(of: header, range: searchStart..<copy.endIndex),
                    "\(header) is missing or out of order: \(copy)"
                )
                headers.append(range)
                searchStart = range.upperBound
            }
            let healthSection = copy[headers[3].upperBound..<headers[4].lowerBound]
            #expect(
                healthSection.trimmingCharacters(in: .whitespaces) == "workout import",
                "the Apple Health section holds the one row: \(healthSection)"
            )

            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Workout import") == true } }
            let row = try #require(elements.first { $0.accessibilityLabel?.contains("Workout import") == true })
            #expect(row.accessibilityActivate())

            let pushed = try await screen.copy {
                $0.contains(AppleHealthSettingsView.connectedDetail.lowercased())
                    || $0.contains(AppleHealthSettingsView.offDetail.lowercased())
                    || $0.contains(AppleHealthSettingsView.notOfferedDetail.lowercased())
            }
            #expect(!pushed.contains("purchases"), "the row pushed the Apple Health screen: \(pushed)")
        }
    }

    // MARK: - Import older workouts

    @Test("Import older workouts opens the same history screen as 07a, in the Connect flow's chrome")
    func importOlderWorkoutsOpensTheHistoryScreen() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40)
        harness.addWorkout(daysAgo: 400, steps: nil, minutes: 50, windowSteps: 5_000)

        try await RenderedScreen.host(section(harness), size: CGSize(width: 402, height: 874), settle: .turns(40)) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.contains("Import older workouts") == true } }
            let row = try #require(elements.first { $0.accessibilityLabel?.contains("Import older workouts") == true })
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

    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)])
    func theOlderWorkoutsScreenKeepsItsButtonsOnScreen(size: CGSize) async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        for index in 0..<30 {
            harness.addWorkout(daysAgo: Double(40 + index * 3), steps: 23_000, minutes: 200)
        }
        let view = AppleHealthOlderWorkoutsView(
            viewModel: AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }),
            onClose: {}
        )
        .environment(\.onboardingReduceMotionOverride, true)
        .modelContainer(harness.container)

        try await RenderedScreen.host(view, size: size, settle: .turns(60)) { screen in
            let copy = try await screen.copy { $0.contains("to my history") }
            #expect(copy.contains("690,000"), "\(copy)")
            #expect(copy.contains("that's everest"), "\(copy)")
            let primary = try #require(try await screen.frame(ofElementLabelled: "ADD 30 TO MY HISTORY"))
            #expect(screen.bounds.contains(primary), "the button \(primary) runs off the screen")
            let secondary = try #require(try await screen.frame(ofElementLabelled: "Not now"))
            #expect(screen.bounds.contains(secondary), "\(secondary)")
            #expect(secondary.minY >= primary.maxY, "in the reserved slot under the button")
            let close = try #require(try await screen.frame(ofElementLabelled: "Close"))
            #expect(close.minY >= 0 && close.maxY < primary.minY, "\(close)")
            try screen.photograph(named: "settings-apple-health-older-workouts-\(Int(size.height))")
        }
    }

    // MARK: - The range picker

    private func rangeChoice() -> HealthHistoryChoice {
        let now = Date()
        func workout(daysAgo: Double) -> HealthWorkoutSnapshot {
            let start = now.addingTimeInterval(-daysAgo * 86_400)
            return HealthWorkoutSnapshot(uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(2_400), steps: 3_000)
        }
        return HealthHistoryChoice(
            history: HealthHistory(workouts: [workout(daysAgo: 10), workout(daysAgo: 200), workout(daysAgo: 800)]),
            climbs: [],
            now: now
        )
    }

    @Test("The picker lists everything, the last year, the last 90 days and a date, each with its count")
    func thePickerListsTheFourRangesWithTheirCounts() async throws {
        let choice = rangeChoice()
        var closes = 0

        try await RenderedScreen.host(
            HealthHistoryRangeSheet(choice: choice) { closes += 1 },
            // A sheet has no status bar above it; the hosted window does, so it is that much taller.
            size: CGSize(width: 402, height: HealthHistoryRangeSheet.height + 62)
        ) { screen in
            let copy = try await screen.copy { $0.contains("last 90 days") }
            #expect(copy.contains("how far back?"), "\(copy)")
            #expect(copy.contains("everything, 3 workouts"), "\(copy)")
            #expect(copy.contains("last year, 2 workouts"), "\(copy)")
            #expect(copy.contains("last 90 days, 1 workout"), "\(copy)")
            #expect(copy.contains("since"), "\(copy)")
            #expect(copy.contains("add the rest any time in settings."), "\(copy)")
            #expect(copy.contains("done"), "\(copy)")
            let since = try #require(try await screen.frame(ofElementLabelled: "Since"))
            let note = try #require(try await screen.frame(ofElementLabelled: "Add the rest any time in Settings."))
            #expect(since.maxY <= note.minY, "all four rows fit above the note without scrolling: \(since) \(note)")
            try screen.photograph(named: "health-history-range-picker")

            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel == "Last year, 2 workouts" } }
            let everything = try #require(elements.first { $0.accessibilityLabel == "Everything, 3 workouts" })
            #expect(everything.accessibilityTraits.contains(.selected), "everything is the default")
            let lastYear = try #require(elements.first { $0.accessibilityLabel == "Last year, 2 workouts" })
            #expect(lastYear.accessibilityActivate())
            #expect(choice.range == .lastYear)
            #expect(choice.primaryTitle == "Add 2 to my history")
            #expect(closes == 1, "a preset is one tap and the sheet closes")
        }
    }

    @Test("A range that holds no workouts cannot be picked")
    func aRangeWithNothingInItCannotBePicked() async throws {
        let now = Date()
        let start = now.addingTimeInterval(-800 * 86_400)
        let choice = HealthHistoryChoice(
            history: HealthHistory(workouts: [
                HealthWorkoutSnapshot(uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(2_400), steps: 3_000)
            ]),
            climbs: [],
            now: now
        )

        try await RenderedScreen.host(
            HealthHistoryRangeSheet(choice: choice) {},
            size: CGSize(width: 402, height: HealthHistoryRangeSheet.height)
        ) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel == "Last year, None" } }
            let lastYear = try #require(elements.first { $0.accessibilityLabel == "Last year, None" })
            #expect(lastYear.accessibilityTraits.contains(.notEnabled))
            _ = lastYear.accessibilityActivate()
            #expect(choice.range == .everything)
            #expect(choice.primaryTitle == "Add 1 to my history")
        }
    }

    @Test("The range row on the history screen opens the picker")
    func theRangeRowOpensThePicker() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40)
        harness.addWorkout(daysAgo: 400, steps: 4_000, minutes: 50)
        let view = AppleHealthOlderWorkoutsView(
            viewModel: AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }),
            onClose: {}
        )
        .environment(\.onboardingReduceMotionOverride, true)
        .modelContainer(harness.container)

        try await RenderedScreen.host(view, size: CGSize(width: 402, height: 874), settle: .turns(40)) { screen in
            let elements = try await screen.elements { $0.contains { $0.accessibilityLabel?.hasPrefix("Time range, Everything since") == true } }
            let row = try #require(elements.first { $0.accessibilityLabel?.hasPrefix("Time range, Everything since") == true })
            #expect(row.accessibilityTraits.contains(.button))
            #expect(row.accessibilityActivate())

            let copy = try await screen.copy { $0.contains("how far back?") }
            #expect(copy.contains("everything, 2 workouts"), "\(copy)")
            #expect(copy.contains("last 90 days, 1 workout"), "\(copy)")
        }
    }

    @Test
    func itListsOnlyWhatTheBackfillCanStillBringIn() async throws {
        let harness = try AppleHealthImportHarness()
        let older = harness.addWorkout(daysAgo: 60, steps: 3_000)
        let olderStill = harness.addWorkout(daysAgo: 400, steps: nil, windowSteps: 4_000)
        let alreadyIn = harness.addWorkout(daysAgo: 90, steps: 2_000)
        let turnedAway = harness.addWorkout(daysAgo: 120, steps: 2_000)
        harness.addWorkout(daysAgo: 5, steps: 2_500)                              // since joining: the pass's
        harness.addWorkout(daysAgo: 200, steps: 2_000, minutes: 25 * 60)          // not a climb
        await harness.service.importHistory(matching: [alreadyIn.uuid.uuidString, turnedAway.uuid.uuidString])
        let removed = try #require(try harness.climbs().first { $0.healthKitUUID == turnedAway.uuid.uuidString })
        await harness.service.removeImportedClimb(workoutID: removed.id)

        let viewModel = AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }, now: { harness.referenceNow })
        await viewModel.load()

        guard case .found(let choice) = viewModel.state else {
            Issue.record("expected older workouts, got \(viewModel.state)")
            return
        }
        #expect(Set(choice.summary.workoutIDs) == [older.uuid.uuidString, olderStill.uuid.uuidString])
        #expect(choice.summary.knownSteps == 7_000)
        #expect(try harness.records().count == 2, "looking files nothing new")
    }

    @Test
    func addingFilesOnlyTheRangeThroughTheBackfillOffTheBoards() async throws {
        let harness = try AppleHealthImportHarness()
        let inside = harness.addWorkout(daysAgo: 60, steps: 3_000)
        let outside = harness.addWorkout(daysAgo: 400, steps: 4_000)
        let viewModel = AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }, now: { harness.referenceNow })
        await viewModel.load()
        guard case .found(let choice) = viewModel.state else {
            Issue.record("expected older workouts, got \(viewModel.state)")
            return
        }

        choice.select(.last90Days)
        let landed = await viewModel.addToHistory()

        #expect(landed)
        #expect(viewModel.errorMessage == nil)
        let climbs = try harness.climbs()
        #expect(climbs.map(\.healthKitUUID) == [inside.uuid.uuidString])
        #expect(climbs.first?.leaderboardStatus == .excluded, "history never reaches a board")
        #expect(try harness.record(outside) == nil, "outside the range, so never filed")
        #expect(harness.notifier.imported.isEmpty)

        // What was left out is still there to add next time.
        let again = AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }, now: { harness.referenceNow })
        await again.load()
        guard case .found(let rest) = again.state else {
            Issue.record("expected the rest, got \(again.state)")
            return
        }
        #expect(rest.summary.workoutIDs == [outside.uuid.uuidString])
    }

    @Test
    func nothingOlderSaysSoAndAFailedReadIsNeverSaidAsNothing() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 5, steps: 2_500)
        let empty = AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] })
        await empty.load()
        guard case .nothing = empty.state else {
            Issue.record("expected nothing, got \(empty.state)")
            return
        }

        harness.reader.readError = CocoaError(.fileReadUnknown)
        let failed = AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] })
        await failed.load()
        guard case .unavailable = failed.state else {
            Issue.record("expected unavailable, got \(failed.state)")
            return
        }
    }

    @Test
    func anImportThatIsDeferredKeepsTheScreenAndSaysToTryAgain() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 60, steps: 3_000)
        let viewModel = AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }, now: { harness.referenceNow })
        await viewModel.load()

        harness.reader.readError = CocoaError(.fileReadUnknown)
        let landed = await viewModel.addToHistory()

        #expect(!landed)
        #expect(viewModel.errorMessage == AppleHealthOlderWorkoutsViewModel.importFailedMessage)
        #expect(try harness.climbs().isEmpty)

        harness.reader.readError = nil
        #expect(await viewModel.addToHistory(), "the second try lands it")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("The empty states read whole")
    func theEmptyStatesReadWhole() async throws {
        let harness = try AppleHealthImportHarness()
        let view = AppleHealthOlderWorkoutsView(
            viewModel: AppleHealthOlderWorkoutsViewModel(importService: harness.service, loadClimbs: { [] }),
            onClose: {}
        )
        .modelContainer(harness.container)

        try await RenderedScreen.host(view, size: CGSize(width: 402, height: 874), settle: .turns(40)) { screen in
            let copy = try await screen.copy { $0.contains("done") }
            #expect(copy.contains(AppleHealthOlderWorkoutsView.nothingTitle.lowercased()), "\(copy)")
            #expect(copy.contains(AppleHealthOlderWorkoutsView.nothingDetail.lowercased()), "\(copy)")
            #expect(!copy.contains("not now"), "one way out is enough: \(copy)")
            try screen.photograph(named: "settings-apple-health-older-workouts-none")
        }
    }
}
