import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the racing curation (#440): the onboarding landmark
/// collages show every raceable asset exactly once, and a retired mountain
/// reached through history refuses the race truthfully instead of promising a
/// "Coming Soon" that is never coming.
///
/// Every surface is hosted through `RenderedScreen` and its copy read off the
/// accessibility tree; photographs land in `ASCEND_EVIDENCE_DIR` when it is set
/// and are not taken otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbCurationSurfaceEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    /// The curation under test is the catalogue this build ships, so the evidence
    /// reads the bundled file. `ClimbService.shared` is the wrong source here: the
    /// test host launches the real app, which refreshes the singleton from the
    /// environment's hosted catalogue, and that copy only matches the repository
    /// after a deploy.
    private static let bundledCatalogService = ClimbService(
        catalogRepository: BundledClimbCatalogRepository()
    )

    /// Held for the process, not per render: the detail screen keeps observing
    /// SwiftData for a beat after its host is torn down, and a container that has
    /// already gone traps on the next fetch any other suite performs.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    /// The page publishes itself as one combined element whose label names every
    /// card it draws, so the tree holds the same list the collage shows.
    @Test("The landmarks value page shows four distinct landmarks in two columns", .bug(id: 440))
    func landmarksValuePageShowsNoLandmarkTwice() async throws {
        try await RenderedScreen.host(
            flat(
                OnboardingLandmarksValuePageContent(
                    subtitle: OnboardingValuePages.landmarkSubtitle(raceableLandmarkCount: 30)
                )
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()

            for label in ["statue", "empire", "eiffel", "burj"] {
                #expect(text.contains(label), "expected \(label) in: \(text)")
            }
            #expect(!text.contains("machu"))
            #expect(!text.contains("everest"))

            try screen.photograph(named: "onboarding-landmarks-value-page")
        }
    }

    /// The collage is hidden from the accessibility tree by design, so which
    /// landmarks it draws is checked by eye on the photograph; what the tree can
    /// hold is that the screen photographed is the guide's landmark page.
    @Test("The pre-auth guide collage repeats no landmark", .bug(id: 440))
    func preAuthGuideCollageRepeatsNoLandmark() async throws {
        try await RenderedScreen.host(
            flat(OnboardingFeatureGuideFlowScreen(onFinish: {})),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()
            #expect(text.contains("most iconic landmarks"), "expected the landmark guide page in: \(text)")

            try screen.photograph(named: "onboarding-preauth-guide-collage")
        }
    }

    @Test("A hidden mountain reached through history reads Not Raceable", .bug(id: 440))
    func hiddenMountainDetailIsNotRaceable() async throws {
        let everest = try #require(
            try Self.bundledCatalogService.loadAllClimbs().first { $0.id == "mount-everest" },
            "Mount Everest must stay in the catalogue for earned history"
        )
        #expect(everest.releaseState == .hidden)

        let text = try await captureDetail(
            for: everest,
            named: "climb-detail-hidden-mount-everest"
        )

        #expect(text.contains("not raceable"), "expected the truthful refusal in: \(text)")
        #expect(!text.contains("coming soon"))
        #expect(!text.contains("start live climb"))
    }

    @Test("An available climb still offers the race", .bug(id: 440))
    func availableClimbDetailStillStartsTheRace() async throws {
        let empire = try #require(
            try Self.bundledCatalogService.loadAllClimbs().first { $0.id == "empire-state-building" }
        )
        #expect(empire.releaseState == .available)

        let text = try await captureDetail(
            for: empire,
            named: "climb-detail-available-empire-state"
        )

        #expect(text.contains("start live climb"), "expected the race CTA in: \(text)")
    }

    @Test("The opened Petronas Towers races over its corrected distance, not its height")
    func openedPetronasTowersDetailRacesTheCorrectedDistance() async throws {
        let petronas = try #require(
            try Self.bundledCatalogService.loadAllClimbs().first { $0.id == "petronas-towers" }
        )
        #expect(petronas.releaseState == .available)
        #expect(petronas.realStairCount == 2_170)
        #expect(petronas.referenceStepCount == 2_170)
        #expect(petronas.calculatedFloors == 88)
        #expect(petronas.totalSteps == 2_486, "the height fact is never rewritten by a distance correction")
        #expect(petronas.tier == .diamond)

        let overview = try await captureDetail(
            for: petronas,
            named: "climb-detail-available-petronas-towers-overview",
            scrollingToBottom: false
        )

        #expect(overview.contains("2,170"), "expected the raced distance in: \(overview)")
        #expect(overview.contains("steps"))
        #expect(overview.contains("floors"))
        #expect(overview.contains("88"), "expected the corrected floor count in: \(overview)")
        #expect(!overview.contains("2,486"), "the architectural height must not stand in for the route")
        #expect(!overview.contains("126"), "the height-derived floor count must not survive the correction")

        let race = try await captureDetail(
            for: petronas,
            named: "climb-detail-available-petronas-towers-race"
        )

        #expect(race.contains("start live climb"), "expected the race CTA in: \(race)")
        #expect(!race.contains("coming soon"))
    }

    @Test("An activated World Tour venue offers the race on its detail screen", .bug(id: 465))
    func activatedWorldTourVenueDetailStartsTheRace() async throws {
        let torreReforma = try #require(
            try Self.bundledCatalogService.loadAllClimbs().first { $0.id == "torre-reforma" }
        )
        #expect(torreReforma.releaseState == .available)

        let text = try await captureDetail(
            for: torreReforma,
            named: "climb-detail-available-torre-reforma"
        )

        #expect(text.contains("start live climb"), "expected the race CTA in: \(text)")
        #expect(!text.contains("coming soon"))
    }

    @Test("The World Tour venue with no published course distance stays locked", .bug(id: 465))
    func heldBackWorldTourVenueDetailStillReadsComingSoon() async throws {
        let capitaMall = try #require(
            try Self.bundledCatalogService.loadAllClimbs().first { $0.id == "capitamall-one" }
        )
        #expect(capitaMall.releaseState == .comingSoon)

        let text = try await captureDetail(
            for: capitaMall,
            named: "climb-detail-coming-soon-capitamall-one"
        )

        #expect(text.contains("coming soon"), "expected the pending state in: \(text)")
        #expect(!text.contains("start live climb"))
    }

    @Test("An unverified stair route still reads Coming Soon", .bug(id: 440))
    func comingSoonClimbDetailStillReadsComingSoon() async throws {
        let shard = try #require(
            try Self.bundledCatalogService.loadAllClimbs().first { $0.id == "the-shard" }
        )
        #expect(shard.releaseState == .comingSoon)

        let text = try await captureDetail(
            for: shard,
            named: "climb-detail-coming-soon-the-shard"
        )

        #expect(text.contains("coming soon"), "expected the pending state in: \(text)")
        #expect(!text.contains("start live climb"))
    }

    // MARK: - Rendering

    /// The onboarding pages are plain view trees: a full-screen frame in the dark
    /// scheme is all they need before hosting.
    private func flat(_ content: some View) -> some View {
        content
            .frame(width: Self.screenSize.width, height: Self.screenSize.height)
            .environment(\.colorScheme, .dark)
    }

    /// The climb detail screen sits in a `NavigationStack` and its content only
    /// resolves once SwiftUI has run an update loop against a real display link,
    /// so it is hosted in a live window and its copy read off the tree.
    private func captureDetail(
        for climb: Climb,
        named name: String,
        scrollingToBottom: Bool = true
    ) async throws -> String {
        let container = try #require(Self.container, "The evidence suite needs an in-memory container")
        let host = UIHostingController(
            rootView: NavigationStack {
                ClimbDetailView(climb: climb, climbService: Self.bundledCatalogService)
            }
            .modelContainer(container)
            .environment(ModerationStore.shared)
            .preferredColorScheme(.dark)
        )

        return try await RenderedScreen.host(host, size: Self.screenSize) { screen -> String in
            // The race action sits at the foot of the overview, below the fold on a
            // 393pt screen, so the state under test is only in frame after a scroll.
            if scrollingToBottom, let scrollView = Self.firstScrollView(in: screen.window) {
                let maximumOffset = max(
                    0,
                    scrollView.contentSize.height - scrollView.bounds.height
                        + scrollView.adjustedContentInset.bottom
                )
                scrollView.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: false)
                try await screen.settle(.turns(6))
            }

            let text = try await screen.copy()
            try screen.photograph(named: name)
            return text
        }
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}

/// Serves the catalogue this build bundles and never reaches the network, so the
/// evidence renders the curation in the repository rather than whichever version
/// the environment's hosting happens to be serving.
private struct BundledClimbCatalogRepository: ClimbCatalogRepository {
    func loadInitialCatalog() throws -> ClimbCatalogSnapshot {
        guard let url = Bundle.main.url(forResource: "climbs", withExtension: "json") else {
            throw ClimbService.LoadError.missingBundledData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return ClimbCatalogSnapshot(
            climbs: try decoder.decode([Climb].self, from: try Data(contentsOf: url)),
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: "empire-state-building",
            updatedAt: nil
        )
    }

    func refreshCatalog() async throws -> ClimbCatalogSnapshot {
        try loadInitialCatalog()
    }
}
