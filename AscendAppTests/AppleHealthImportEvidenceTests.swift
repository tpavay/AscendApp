import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// The Apple Health import screens, hosted as shipped and read back off their accessibility trees.
///
/// Photographs are written to `ASCEND_EVIDENCE_DIR` when it is set - the same set the handoff's
/// mock screens 03 to 13 describe - and copy is asserted either way.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppleHealthImportEvidenceTests {
    // MARK: - Climb sheet

    /// The picks the handoff's mock screens 03 to 05 show.
    private static let mockPicks = HomeStartPicks(
        landmarkLine: "Today: DC Tower 1 · 1,412 steps",
        routineLine: "Today: Pyramid Climb · 20 min"
    )

    @Test("The Climb sheet's Health button is Connect Health, View imports with a count, or plain View imports")
    func theClimbSheetShowsTheRightHealthButtonForEachState() async throws {
        for (entry, name, expectedCopy, forbiddenCopy) in [
            (AppleHealthEntry.connect, "import-03-sheet-not-connected", "connect health", "view imports"),
            (AppleHealthEntry.viewImports(badge: 2), "import-04-sheet-ask", "view imports", "connect health"),
            (AppleHealthEntry.viewImports(badge: 0), "import-05-sheet-auto", "view imports", "connect health"),
        ] {
            try await RenderedScreen.host(
                HomeStartActionSheet(
                    onSelect: { _ in },
                    onLogIt: {},
                    healthEntry: entry,
                    picks: Self.mockPicks
                )
                    .frame(width: 390)
                    .background(Color.black),
                size: CGSize(width: 390, height: 640)
            ) { screen in
                let copy = try await screen.copy { $0.contains("already climbed") }
                #expect(copy.contains("log it"))
                #expect(copy.contains("pick how today goes"), "\(copy)")
                #expect(copy.contains("the mountain, with whoever you want."), "\(copy)")
                #expect(copy.contains("today: dc tower 1 · 1,412 steps"), "\(copy)")
                #expect(copy.contains("today: pyramid climb · 20 min"), "\(copy)")
                #expect(copy.components(separatedBy: "see all").count - 1 == 2, "\(copy)")
                #expect(copy.contains(expectedCopy), "\(copy)")
                #expect(!copy.contains(forbiddenCopy), "\(copy)")
                if case .viewImports(let badge) = entry, badge > 0 {
                    #expect(copy.contains("\(badge)"), "the red count is on the button: \(copy)")
                }
                try screen.photograph(named: name)
            }
        }
    }

    @Test("A device with no Health shows Log it alone")
    func aDeviceWithNoHealthShowsLogItAlone() async throws {
        try await RenderedScreen.host(
            HomeStartActionSheet(onSelect: { _ in }, onLogIt: {}, healthEntry: nil)
                .frame(width: 402)
                .background(Color.black),
            size: CGSize(width: 402, height: 640)
        ) { screen in
            let copy = try await screen.copy { $0.contains("already climbed") }
            #expect(copy.contains("log it"))
            #expect(!copy.contains("health"), "\(copy)")
        }
    }

    // MARK: - Imports

    @Test("Imports with auto-import off: Not imported with + and Import all, Imported with a check")
    func importsAskShowsWaitingAndImported() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        await harness.service.setAutoImportEnabled(false)
        harness.addWorkout(daysAgo: 0.05, steps: 4_912, minutes: 62.83)
        harness.addWorkout(daysAgo: 2, steps: 3_207, minutes: 41.2)
        let older = harness.addWorkout(daysAgo: 9, steps: 2_744, minutes: 35.08)
        await harness.service.syncNow()
        _ = await harness.service.importRecords(withUUIDs: [older.uuid.uuidString])

        try await RenderedScreen.host(
            NavigationStack { AppleHealthImportsView(viewModel: AppleHealthImportsViewModel(service: harness.service)) }
                .modelContainer(harness.container)
        ) { screen in
            let copy = try await screen.copy { $0.contains("import all") }

            #expect(copy.contains("imports"))
            #expect(copy.contains("auto-import"))
            #expect(copy.contains("you choose which workouts to import."), "\(copy)")
            #expect(copy.contains("not imported"))
            #expect(copy.contains("4,912 steps"))
            #expect(copy.contains("3,207 steps"))
            #expect(copy.contains("import all (2)"), "\(copy)")
            #expect(copy.contains("imported"))
            #expect(copy.contains("2,744 steps"))
            #expect(copy.contains("earlier"))
            try screen.photograph(named: "import-06-imports-ask")
        }
    }

    @Test("Import all moves the rows, says how many, and offers Undo")
    func importAllShowsTheUndoToast() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        await harness.service.setAutoImportEnabled(false)
        harness.addWorkout(daysAgo: 0.05, steps: 4_912, minutes: 62.83)
        harness.addWorkout(daysAgo: 0.9, steps: 3_207, minutes: 41.2)
        await harness.service.syncNow()
        let viewModel = AppleHealthImportsViewModel(service: harness.service)

        try await RenderedScreen.host(
            NavigationStack { AppleHealthImportsView(viewModel: viewModel) }
                .modelContainer(harness.container)
        ) { screen in
            _ = try await screen.copy { $0.contains("import all") }
            await viewModel.importAll(try harness.records().map(\.workoutUUID))

            let copy = try await screen.copy { $0.contains("2 climbs imported") }
            #expect(copy.contains("undo"))
            #expect(!copy.contains("import all"), "nothing is left to import: \(copy)")
            // The screen reads the wall clock, so on a Monday morning both workouts started in
            // last week's Monday-to-Sunday window and land under Earlier, never This week.
            let calendar = WeekConfiguration.calendar()
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
            let starts = try harness.records().map(\.startDate)
            if starts.allSatisfy({ $0 >= weekStart }) {
                #expect(copy.contains("this week"), "\(copy)")
            } else if starts.allSatisfy({ $0 < weekStart }) {
                #expect(copy.contains("earlier"), "\(copy)")
                #expect(!copy.contains("this week"), "\(copy)")
            } else {
                #expect(copy.contains("this week") && copy.contains("earlier"), "\(copy)")
            }
            try screen.photograph(named: "import-07-imports-done")
        }

        #expect(viewModel.toast?.batch.count == 2)
        await viewModel.undo()
        #expect(try harness.climbs().isEmpty)
        #expect(viewModel.toast == nil)
    }

    @Test("Imports with auto-import on shows only Imported, grouped by date")
    func importsAutoShowsOnlyImported() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 0.05, steps: 4_912, minutes: 62.83)
        harness.addWorkout(daysAgo: 2, steps: 3_207, minutes: 41.2)
        harness.addWorkout(daysAgo: 9, steps: 2_744, minutes: 35.08)
        harness.addWorkout(daysAgo: 13, steps: nil, minutes: 28.6)
        await harness.service.syncNow()

        try await RenderedScreen.host(
            NavigationStack { AppleHealthImportsView(viewModel: AppleHealthImportsViewModel(service: harness.service)) }
                .modelContainer(harness.container)
        ) { screen in
            let copy = try await screen.copy { $0.contains("earlier") }

            #expect(copy.contains("new stair stepper workouts are imported for you."), "\(copy)")
            #expect(!copy.contains("not imported"))
            #expect(!copy.contains("import all"))
            #expect(copy.contains("4,912 steps"))
            #expect(copy.contains("add steps"), "a climb with no steps asks for them instead of printing a dash: \(copy)")
            #expect(!copy.contains("— steps"), "\(copy)")
            try screen.photograph(named: "import-08-imports-auto")
        }
    }

    // MARK: - Connect

    @Test("The connect screens read as the mocks do")
    func theConnectFlowScreens() async throws {
        try await RenderedScreen.host(
            AppleHealthConnectView(onConnect: {}, onClose: {})
        ) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            #expect(copy.contains("your workouts,"), "\(copy)")
            #expect(copy.contains("counted for you."))
            #expect(copy.contains("any device or app that saves there"))
            #expect(copy.contains("not now"))
            #expect(copy.contains("close"))
            #expect(copy.contains("tap turn on all, then allow."), "the copy matches the iOS sheet: \(copy)")
            #expect(!copy.contains("top right"), "iOS puts Allow at the bottom: \(copy)")
            #expect(!copy.contains("watch"), "no wearable is named: \(copy)")
            try screen.photograph(named: "import-09-connect")
        }

        try await RenderedScreen.host(
            AppleHealthImportChoiceView(
                choosesAutomatic: .constant(true),
                summary: "We found 2 stair stepper workouts. New ones will keep coming in.",
                isWorking: false,
                onContinue: {}
            )
        ) { screen in
            let copy = try await screen.copy { $0.contains("continue") }
            #expect(copy.contains("apple health connected"))
            #expect(copy.contains("how should we"))
            #expect(copy.contains("import them?"))
            #expect(copy.contains("import automatically"))
            #expect(copy.contains("let me choose"))
            #expect(copy.contains("you can change this anytime in settings."))
            try screen.photograph(named: "import-11-choose")
        }
    }

    @Test("The close X and the primary button sit in the same place on every screen of the connect flow")
    func theFlowChromeDoesNotMoveBetweenScreens() async throws {
        var closeFrame: CGRect?
        var safeAreaTop: CGFloat = 0
        var primaryFrames: [CGRect] = []

        try await RenderedScreen.host(AppleHealthConnectView(onConnect: {}, onClose: {})) { screen in
            safeAreaTop = screen.window.safeAreaInsets.top
            closeFrame = try await screen.frame(ofElementLabelled: "Close")
            let texts = try await screen.texts()
            primaryFrames.append(try #require(texts.first { $0.text.uppercased() == "CONNECT APPLE HEALTH" }?.frame))
        }
        try await RenderedScreen.host(
            AppleHealthImportChoiceView(
                choosesAutomatic: .constant(true),
                summary: "We found 2 stair stepper workouts. New ones will keep coming in.",
                isWorking: false,
                onContinue: {}
            )
        ) { screen in
            let texts = try await screen.texts()
            primaryFrames.append(try #require(texts.first { $0.text.uppercased() == "CONTINUE" }?.frame))
        }

        let close = try #require(closeFrame)
        #expect(close.minX == HealthFlowChrome.leadingInset, "the X sits at the flow's leading inset: \(close)")
        #expect(
            close.minY == safeAreaTop + HealthFlowChrome.topInset,
            "the X sits just under the safe area's top, not 54 points down: \(close) under \(safeAreaTop)"
        )
        #expect(primaryFrames.count == 2)
        #expect(
            abs(primaryFrames[0].midY - primaryFrames[1].midY) < 1,
            "the primary button is where it was: \(primaryFrames)"
        )
    }

    // MARK: - After an automatic import

    @Test("The Home strip and the quick edit sheet read as the mocks do")
    func theStripAndTheQuickEditSheet() async throws {
        let start = Date()
        try await RenderedScreen.host(
            HomeHealthImportStrip(
                notice: AppleHealthImportService.HomeNotice(
                    workoutID: UUID(), startDate: start, steps: 4_912, duration: 3_770
                ),
                onEdit: {}
            )
            .padding(16)
            .frame(width: 402)
            .background(Color.black),
            size: CGSize(width: 402, height: 160)
        ) { screen in
            let copy = try await screen.copy { $0.contains("edit") }
            #expect(copy.contains("imported from apple health"))
            #expect(copy.contains("today · 4,912 steps · 1:02:50"), "\(copy)")
            try screen.photograph(named: "import-12-home-strip")
        }

        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 0.02, steps: 4_912, minutes: 62.83, averageHeartRate: 127)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)
        climb.effortRating = 4
        try harness.context.save()

        try await RenderedScreen.host(
            ImportedClimbQuickEditSheet(workout: climb, importService: harness.service)
                .modelContainer(harness.container),
            size: CGSize(width: 402, height: 760)
        ) { screen in
            let copy = try await screen.copy { $0.contains("remove this climb") }
            #expect(copy.contains("climb imported"))
            #expect(copy.contains("from apple health"))
            #expect(copy.contains("1:02:50"))
            #expect(copy.contains("avg bpm"))
            #expect(copy.contains("127"))
            #expect(copy.contains("exactly what apple health recorded. tap to change it."), "\(copy)")
            #expect(copy.contains("add a note"))
            #expect(copy.contains("photo"))
            #expect(copy.contains("effort · 4"))
            #expect(copy.contains("done"))
            try screen.photograph(named: "import-13-quick-edit")
        }
    }
}
