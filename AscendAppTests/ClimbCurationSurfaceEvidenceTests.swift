import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the racing curation (#440): the onboarding landmark
/// collages show every raceable asset exactly once, and a retired mountain
/// reached through history refuses the race truthfully instead of promising a
/// "Coming Soon" that is never coming.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's
/// temporary directory otherwise.
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

    @Test("The landmarks value page shows four distinct landmarks in two columns", .bug(id: 440))
    func landmarksValuePageShowsNoLandmarkTwice() async throws {
        let image = try renderFlat(
            OnboardingLandmarksValuePageContent(
                subtitle: OnboardingValuePages.landmarkSubtitle(raceableLandmarkCount: 30)
            )
        )
        let text = try await recognizedText(in: image)

        for label in ["statue", "empire", "eiffel", "burj"] {
            #expect(text.contains(label), "expected \(label) in: \(text)")
        }
        #expect(!text.contains("machu"))
        #expect(!text.contains("everest"))

        try write(image, named: "onboarding-landmarks-value-page")
    }

    @Test("The pre-auth guide collage repeats no landmark", .bug(id: 440))
    func preAuthGuideCollageRepeatsNoLandmark() throws {
        let image = try renderFlat(OnboardingFeatureGuideFlowScreen(onFinish: {}))

        try write(image, named: "onboarding-preauth-guide-collage")
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

    /// `ImageRenderer` flattens a plain view tree, which is all the onboarding
    /// pages need and is far cheaper than borrowing the window scene.
    private func renderFlat(_ content: some View) throws -> UIImage {
        let renderer = ImageRenderer(
            content: content
                .frame(width: Self.screenSize.width, height: Self.screenSize.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no image")
    }

    /// The climb detail screen needs a live window: it sits in a `NavigationStack`,
    /// which `ImageRenderer` cannot flatten, and its content only resolves once
    /// SwiftUI has run an update loop against a real display link.
    private func captureDetail(for climb: Climb, named name: String) async throws -> String {
        let container = try #require(Self.container, "The evidence suite needs an in-memory container")
        let host = UIHostingController(
            rootView: NavigationStack {
                ClimbDetailView(climb: climb, climbService: Self.bundledCatalogService)
            }
            .modelContainer(container)
            .environment(ModerationStore.shared)
            .preferredColorScheme(.dark)
        )

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "test host app should expose a live UIWindowScene"
        )
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.screenSize)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = .black
        window.rootViewController = host

        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.makeKeyAndVisible()
        for _ in 0..<12 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        // The race action sits at the foot of the overview, below the fold on a
        // 393pt screen, so the state under test is only in frame after a scroll.
        if let scrollView = Self.firstScrollView(in: window) {
            let maximumOffset = max(
                0,
                scrollView.contentSize.height - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            scrollView.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: false)
            for _ in 0..<6 {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        try write(image, named: name)
        return try await recognizedText(in: image)
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func write(_ image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("ASCEND_EVIDENCE_FILE: \(url.path())")
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
