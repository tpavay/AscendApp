import Foundation
import HealthKit
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing proof that manual logging and Apple Health workout import are gone from every
/// surface a climber can reach, and that Apple Health enrichment survived the removal (#437).
///
/// Every surface here is the shipped view, not a stand-in, hosted in a live window through
/// `RenderedScreen`, and every claim about copy is read back off the screen's accessibility tree
/// rather than asserted against a string constant - a string a screen no longer shows would still
/// pass a string comparison, and a label the tree no longer publishes is exactly what "gone from
/// every surface" means.
///
/// Photographs are written to `ASCEND_EVIDENCE_DIR` when it is set and not taken otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ManualLoggingAndImportRemovalEvidenceTests {
    /// Words that would mean the removal is incomplete, checked as whole words so "Manage" cannot
    /// read as "manual" and "Imported" cannot hide inside a longer token.
    private static let forbiddenWords: Set<String> = [
        "import", "imports", "imported", "importing",
        "manual", "manually",
        "log", "logs", "logged", "logging",
        "tracker", "tracking",
    ]

    // MARK: - The permission prompt

    /// The requested read set is the only place a climber is ever shown what Ascend takes from
    /// Health, and iOS builds that sheet from exactly this set. Workouts, steps and resting energy
    /// were all on it before; none of the three is used by enrichment (#353).
    @Test("Health asks only for what enrichment writes back onto a climb")
    func healthPromptRequestsOnlyEnrichmentReadTypes() throws {
        let requested = HealthKitAuthorizationClient.shared.readTypes
        let identifiers = Set(requested.map(\.identifier)).sorted()

        #expect(
            identifiers == [
                HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                HKQuantityTypeIdentifier.heartRate.rawValue,
            ].sorted(),
            "Ascend asks Health for \(identifiers). Enrichment writes back heart rate and calories and nothing else."
        )
        #expect(
            requested.contains(HKObjectType.workoutType()) == false,
            "requesting workoutType() is the permission that made importing someone else's workout possible"
        )

        // The sentence iOS prints above that same sheet.
        let usageDescription = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String,
            "the host app bundle should carry NSHealthShareUsageDescription"
        )
        // Read out of the built bundle rather than off `AscendApp/Info.plist`, because the file is
        // not the last word: `INFOPLIST_KEY_NSHealthShareUsageDescription` in the target's build
        // settings overrides it, and only the bundle says what iOS will actually print.
        let lowercased = usageDescription.lowercased()
        let overrideHint = """
        This is the string iOS prints above the Health sheet, read out of the built app bundle. \
        If it does not match AscendApp/Info.plist, the target's \
        INFOPLIST_KEY_NSHealthShareUsageDescription build setting is overriding the file.
        """
        #expect(!lowercased.contains("import"), "The Health prompt still promises importing: \"\(usageDescription)\". \(overrideHint)")
        #expect(
            !lowercased.contains("resting energy"),
            "The Health prompt still names resting energy, which Ascend no longer requests: \"\(usageDescription)\". \(overrideHint)"
        )
        #expect(
            !lowercased.contains("step"),
            "The Health prompt still names steps, which Ascend no longer requests: \"\(usageDescription)\". \(overrideHint)"
        )
        // The prompt must name exactly what the read set above asks for, so the sentence and the
        // requested types cannot drift apart.
        #expect(lowercased.contains("heart rate"), "The Health prompt no longer names heart rate: \"\(usageDescription)\". \(overrideHint)")
        #expect(lowercased.contains("active energy"), "The Health prompt no longer names active energy: \"\(usageDescription)\". \(overrideHint)")

        // The write-permission string is merged from the same build settings, so it drifts the same
        // way. Ascend never writes to Health, but while the key ships it may not promise importing.
        if let updateDescription = Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") as? String {
            #expect(
                !updateDescription.lowercased().contains("import"),
                "NSHealthUpdateUsageDescription still promises importing: \"\(updateDescription)\". \(overrideHint)"
            )
        }

        try Self.writeText(
            """
            Health permission prompt, as iOS will build it
            ------------------------------------------------
            NSHealthShareUsageDescription:
              \(usageDescription)

            Requested read types (HealthKitAuthorizationClient.readTypes):
            \(identifiers.map { "  - \($0)" }.joined(separator: "\n"))

            Requested share types: (none)
            workoutType() requested: \(requested.contains(HKObjectType.workoutType()))
            """,
            named: "health-permission-request.txt"
        )
    }

    /// The climbs list used to offer "Manual Entry" and "Imported Workout" as source filters. Both
    /// filtered for something a climber can no longer produce.
    @Test("The climbs-list source filter offers only a source Ascend can still record")
    func climbsListFilterOffersOnlyLiveSources() {
        #expect(WorkoutSource.filterOptions == [.headphoneMotion])
    }

    // MARK: - The screens

    /// Hosts every surface that used to carry a logging or import affordance, and reads the copy
    /// back off its accessibility tree.
    @Test("No climber-facing surface offers manual logging or an Apple Health import")
    func climberFacingSurfacesPromiseNoLoggingOrImport() async throws {
        let snapshot = HealthKitSyncStateSnapshot.capture()
        let statusSnapshot = HealthKitAuthorizationClient.shared.authorizationRequestStatus
        defer {
            snapshot.restore()
            HealthKitAuthorizationClient.shared.authorizationRequestStatus = statusSnapshot
        }

        let container = try Self.makeContainer()

        // Home -> START. "Log Manual Workout" was the fourth row.
        let startText = try await Self.hostedCopy(
            HomeStartActionSheet(onSelect: { _ in })
                .frame(width: 402),
            photographedAs: "01-home-start-sheet"
        ) { $0.contains("just climb") }

        // Climbs tab, nothing recorded yet. Used to read "Tap the + button to log your first workout".
        let emptyText = try await Self.hostedCopy(
            WorkoutListEmptyStateView(effectiveColorScheme: .dark)
                .frame(width: 402, height: 360)
                .background(Color.black),
            photographedAs: "02-climbs-empty-state"
        ) { $0.contains("no climbs yet") }

        // Settings -> Integrations, never connected. The card used to sell importing.
        //
        // The card rather than the whole `IntegrationsView`: the card is the shipped view either
        // way, and it is the one that carried the copy.
        HealthKitSyncState.hasRequestedAuthorization = false
        HealthKitAuthorizationClient.shared.isHealthDataAvailable = true
        let neverConnectedText = try await Self.hostedCopy(
            Self.integrationsScreenBody(container: container),
            photographedAs: "03-apple-health-card-never-connected"
        ) { $0.contains("apple health") }

        // The same screen once Health is connected: the promise that survived the removal.
        HealthKitSyncState.hasRequestedAuthorization = true
        HealthKitAuthorizationClient.shared.authorizationRequestStatus = .unnecessary
        let connectedText = try await Self.hostedCopy(
            Self.integrationsScreenBody(container: container),
            photographedAs: "04-apple-health-card-connected"
        ) { $0.contains("connected") }

        // Manage sheet: the auto-import toggle and "Review workouts" are gone, one enrichment
        // action is left.
        let manageText = try await Self.hostedCopy(
            AppleHealthManageSheet(
                isPresented: .constant(true),
                onCheckNow: {},
                onOpenHealthPermissions: {}
            )
            .frame(width: 402)
            .background(Color.black),
            photographedAs: "05-apple-health-manage-sheet"
        ) { $0.contains("check for heart rate now") }

        let surfaces: [(name: String, text: String)] = [
            ("01-home-start-sheet", startText),
            ("02-climbs-empty-state", emptyText),
            ("03-apple-health-card-never-connected", neverConnectedText),
            ("04-apple-health-card-connected", connectedText),
            ("05-apple-health-manage-sheet", manageText),
        ]

        for surface in surfaces {
            let offenders = Self.forbiddenWords.intersection(Self.words(in: surface.text)).sorted()
            #expect(
                offenders.isEmpty,
                "\(surface.name) still shows \(offenders.joined(separator: ", ")) - read back as: \(surface.text)"
            )
        }

        // The screens are actually the screens, not blanks that trivially contain no bad words.
        #expect(startText.contains("just climb"))
        #expect(startText.contains("race a landmark"))
        #expect(startText.contains("run a routine"))

        #expect(emptyText.contains("no climbs yet"))

        // The boundary this change had to hold: Health is still connectable, and it is still
        // described as attaching heart rate to a climb the climber ran in Ascend.
        #expect(neverConnectedText.contains("apple health"))
        #expect(neverConnectedText.contains("connect"))
        #expect(neverConnectedText.contains("heart rate"))

        #expect(connectedText.contains("connected"))
        #expect(connectedText.contains("heart rate"))

        #expect(manageText.contains("check for heart rate now"))
        #expect(manageText.contains("manage health permissions"))
    }

    /// The boundary the removal had to hold, hosted rather than asserted.
    ///
    /// A climb Ascend recorded itself, with no heart rate on it, run through the real enrichment
    /// coordinator with Health answering over that climb's own window - and the same climb after,
    /// carrying the series. Before, the detail screen says nothing about heart rate; after, the
    /// chart is there.
    @Test("Heart rate still attaches to a climb Ascend recorded")
    func heartRateStillAttachesToAnAscendRecordedClimb() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let container = try Self.makeContainer()
            let modelContext = ModelContext(container)

            let start = Date().addingTimeInterval(-45 * 60)
            let duration: TimeInterval = 1_800
            let climb = Workout(
                name: "Empire State Live Climb",
                date: start,
                duration: duration,
                steps: 1_872,
                floors: 117,
                stepsPerFloor: 16,
                source: .headphoneMotion
            )
            modelContext.insert(climb)
            try modelContext.save()

            #expect(climb.avgHeartRate == nil, "the climb has to start with no heart rate on it")

            let coordinator = AppleHealthEnrichmentService(
                authorizationController: StubAuthorizationController(),
                metricsReader: StubMetricsReader(responses: [
                    WorkoutMetrics(
                        avgHeartRate: 148,
                        maxHeartRate: 174,
                        caloriesBurned: 232,
                        heartRateTimeSeries: Self.heartRateSeries(start: start, duration: duration)
                    )
                ]),
                attemptStore: AppleHealthEnrichmentAttemptStore(
                    defaults: UserDefaults(suiteName: "ManualLoggingAndImportRemovalEvidenceTests")!,
                    key: "test.enrichmentRetry.\(UUID().uuidString)"
                )
            )
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment(modelContext: modelContext)

            #expect(climb.avgHeartRate == 148, "enrichment did not attach heart rate to an Ascend-recorded climb")
            #expect(climb.maxHeartRate == 174)
            #expect(climb.caloriesBurned == 232)
            #expect(climb.heartRateTimeSeries.count > 1)

            // The chart's Avg and Max are the header's own labels, so the tree carries the attached
            // numbers; only the trace itself is drawn.
            let chartText = try await Self.hostedCopy(
                HeartRateChartView(
                    heartRateData: climb.heartRateTimeSeries,
                    workoutStartTime: climb.date,
                    workoutDuration: climb.duration,
                    averageHeartRateBpm: climb.avgHeartRate,
                    maxHeartRateBpm: climb.maxHeartRate
                )
                .padding(20),
                photographedAs: "07-enrichment-still-attaches-heart-rate"
            ) { $0.contains("148") }
            #expect(chartText.contains("148"), "the attached average is not on the chart - read back as: \(chartText)")
            #expect(chartText.contains("174"), "the attached maximum is not on the chart - read back as: \(chartText)")
        }
    }

    /// Nothing writes `.manual` or `.appleHealth` any more, but staging and TestFlight stores hold
    /// rows that carry them and no schema stage was added to rewrite them. They have to keep
    /// drawing, with their numbers intact, next to a climb Ascend recorded itself.
    @Test("Climbs stored before the removal still render in the climbs list")
    func legacySourcedClimbsStillRender() async throws {
        let container = try Self.makeContainer()

        let manual = Workout(
            name: "Hand-Logged Stepper",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 1_800,
            steps: 2_410,
            floors: 150,
            stepsPerFloor: 16,
            source: .manual
        )
        let imported = Workout(
            name: "Imported From Health",
            date: Date(timeIntervalSince1970: 1_779_900_000),
            duration: 2_100,
            steps: 3_128,
            floors: 195,
            stepsPerFloor: 16,
            avgHeartRate: 142,
            source: .appleHealth
        )
        let recorded = Workout(
            name: "CN Tower Live Climb",
            date: Date(timeIntervalSince1970: 1_779_800_000),
            duration: 2_347,
            steps: 3_042,
            floors: 190,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )

        for workout in [manual, imported, recorded] {
            container.mainContext.insert(workout)
        }
        try container.mainContext.save()

        #expect(manual.source == .manual, "the stored raw value must still decode")
        #expect(imported.source == .appleHealth)

        let list = VStack(spacing: 12) {
            WorkoutRowView(workout: manual)
            WorkoutRowView(workout: imported)
            WorkoutRowView(workout: recorded)
        }
        .padding(16)
        .frame(width: 402)
        .background(Color.black)
        .modelContainer(container)

        let text = try await Self.hostedCopy(
            list,
            photographedAs: "06-legacy-sourced-climbs-still-render"
        ) { $0.contains("3,042 steps") }

        #expect(text.contains("2,410 steps"), "the hand-logged climb lost its numbers - read back as: \(text)")
        #expect(text.contains("3,128 steps"), "the imported climb lost its numbers - read back as: \(text)")
        #expect(text.contains("3,042 steps"))
    }

    // MARK: - Rendering

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            WorkoutSyncOutboxEntry.self,
            PendingWorkoutDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A plausible stepper series: warm-up, working effort, a push, then a cool-down.
    private static func heartRateSeries(start: Date, duration: TimeInterval) -> [HeartRateDataPoint] {
        let bpm = [112, 124, 133, 141, 146, 149, 152, 158, 166, 174, 161, 138]
        return bpm.enumerated().map { index, value in
            HeartRateDataPoint(
                timestamp: start.addingTimeInterval(duration * Double(index) / Double(bpm.count)),
                heartRate: value
            )
        }
    }

    /// The Apple Health card laid out the way `IntegrationsView` lays it out.
    private static func integrationsScreenBody(container: ModelContainer) -> some View {
        VStack(spacing: 24) {
            AppleHealthIntegrationCard()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(width: 402)
        .background(Color.black)
        .modelContainer(container)
    }

    /// Hosts `content` at phone width on a black screen, dark, and hands back its on-screen copy
    /// once `isReady` holds - lowercased and space-joined, the way OCR used to. Photographed only
    /// when `ASCEND_EVIDENCE_DIR` is set.
    private static func hostedCopy(
        _ content: some View,
        photographedAs name: String,
        until isReady: @escaping (String) -> Bool = { $0.isEmpty == false }
    ) async throws -> String {
        try await RenderedScreen.host(
            content
                .frame(width: 402)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        ) { screen in
            let text = try await screen.copy(until: isReady)
            try screen.photograph(named: name)
            return text
        }
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    // MARK: - Evidence

    /// Written beside the photographs, and only when this run keeps them.
    private static func writeText(_ text: String, named name: String) throws {
        guard let directory = RenderedScreen.evidenceDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appending(path: name))
    }
}
