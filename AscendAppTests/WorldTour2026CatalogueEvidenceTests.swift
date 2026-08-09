import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Reviewer-facing visual evidence for the 2026 World Tour catalogue additions.
///
/// The catalogue is data, but a climber meets it as pixels: a locked "Coming Soon"
/// preview card when they tap the new pin on the globe, and - until the artwork is
/// uploaded to Storage - a category placeholder behind it. These tests render the
/// shipped views against the shipped catalogue file, read the rendered text back with
/// Vision, and write the sheets a reviewer can look at.
@MainActor
struct WorldTour2026CatalogueEvidenceTests {
    @Test
    func newVenuesRenderAsLockedComingSoonCardsOnTheGlobe() async throws {
        let showcase = try Self.showcase()

        for climb in showcase {
            let card = try renderCard(for: climb)
            let text = try await recognizedText(in: card)

            // A new venue announces itself as locked, never as a climbable distance.
            #expect(text.contains("coming soon"), "\(climb.id) did not read as coming soon")
            #expect(text.contains(climb.city.lowercased()), "\(climb.id) lost its location")
            #expect(!text.contains("steps"), "\(climb.id) offered a distance it can't be raced at")
        }

        try writeEvidence(
            image: try renderSheet(ComingSoonPreviewProof(climbs: showcase)),
            named: "world-tour-2026-coming-soon-cards.png"
        )
    }

    @Test
    func theOutdoorStaircaseRendersTheStairsPlaceholderRatherThanABuilding() async throws {
        let staircase = try Self.climb(id: "sommerbergbahn-stair")
        #expect(staircase.category == "staircase")

        // Hosted in a window rather than flattened, so the artwork's own load pass runs
        // and the sheet shows the settled placeholder a climber sees, not a spinner.
        let sheet = try await hostedSnapshot(
            of: StaircasePlaceholderProof(staircase: staircase),
            size: CGSize(width: 460, height: 420)
        )
        // The hero placeholder wraps the name across lines, so compare without spacing.
        let text = try await recognizedText(in: sheet).replacing(" ", with: "")
        #expect(text.contains("sommerbergbahn"))

        // The two panels differ only by category, so identical pixels would mean the
        // "staircase" case never fired and the default building symbol was drawn.
        let staircasePanel = try renderPanel(for: staircase)
        let asSkyscraper = try renderPanel(for: staircase.recategorised(as: "skyscraper"))
        #expect(try #require(staircasePanel.pngData()) != #require(asSkyscraper.pngData()))

        try writeEvidence(image: sheet, named: "world-tour-2026-staircase-placeholder.png")
    }

    @Test
    func theWholeAdditionSetRendersItsTierAndStepReadout() async throws {
        let additions = try Self.additions()
        #expect(additions.count == 29)

        let sheet = try renderSheet(AdditionRosterProof(climbs: additions))
        let text = try await recognizedText(in: sheet)

        #expect(text.contains("ping an finance centre") || text.contains("ping an"))
        #expect(text.contains("no published course distance"))

        try writeEvidence(image: sheet, named: "world-tour-2026-addition-roster.png")
    }

    // MARK: - Rendering

    private func renderSheet(_ content: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return try #require(renderer.uiImage, "ImageRenderer produced no image")
    }

    private func renderCard(for climb: Climb) throws -> UIImage {
        let renderer = ImageRenderer(
            content: ClimbPreviewCardView(
                summary: ClimbPreviewSummary(climb: climb, isCompleted: false),
                onSelect: {},
                onClose: {}
            )
            .frame(width: 361)
            .padding(16)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no card image")
    }

    private func renderPanel(for climb: Climb) throws -> UIImage {
        let renderer = ImageRenderer(
            content: ClimbArtworkView(
                climb: climb,
                variant: .hero,
                imageRepository: UnuploadedArtworkRepository()
            )
            .frame(width: 200, height: 200)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        return try #require(renderer.uiImage, "ImageRenderer produced no placeholder image")
    }

    /// Hosts the sheet in an offscreen window so the artwork's own `.task` runs and the
    /// settled placeholder is what gets captured.
    ///
    /// The window is deliberately never made key and the capture goes through the layer
    /// rather than `drawHierarchy`: this suite suspends while SwiftUI settles, and a key
    /// window left on top across those suspensions is what the other hosting suites draw
    /// into instead of their own.
    private func hostedSnapshot(of view: some View, size: CGSize) async throws -> UIImage {
        let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for _ in 0..<12 {
            await Task.yield()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
    }

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

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: name))
        #expect(png.count > 5_000)
    }

    // MARK: - The shipped catalogue

    static let additionIDs = [
        "ping-an-finance-centre", "ctf-finance-centre-guangzhou",
        "shanghai-world-financial-center", "sommerbergbahn-stair", "capitamall-one",
        "central-plaza-hong-kong", "875-north-michigan-avenue", "dc-tower-1",
        "yingkai-square", "tk-elevator-test-tower", "varso-tower", "tianjin-tv-tower",
        "macau-tower", "frasers-tower", "torre-reforma", "messeturm-frankfurt",
        "sky-tower-wroclaw", "gran-hotel-bali", "tallinn-tv-tower", "rondo-1",
        "post-tower", "sky-tower-bucharest", "koelnturm", "torre-glories", "az-tower",
        "hyatt-regency-barcelona-tower", "messeturm-basel", "pyramidenkogel",
        "ufo-tower-bratislava"
    ]

    private static let bundledCatalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "AscendApp/Features/Climbs/Resources/climbs.json")

    static func bundledCatalog() throws -> [Climb] {
        let data = try Data(contentsOf: bundledCatalogURL)
        return try JSONDecoder().decode([Climb].self, from: data)
    }

    static func additions() throws -> [Climb] {
        let byID = Dictionary(uniqueKeysWithValues: try bundledCatalog().map { ($0.id, $0) })
        return additionIDs.compactMap { byID[$0] }
    }

    static func climb(id: String) throws -> Climb {
        try #require(try bundledCatalog().first { $0.id == id }, "\(id) is not in the catalogue")
    }

    /// One tall tower, the outdoor staircase, the unsourced mall, and the corrected
    /// Torre Reforma route - the four decisions this change had to make.
    static func showcase() throws -> [Climb] {
        try ["ping-an-finance-centre", "sommerbergbahn-stair", "capitamall-one", "torre-reforma"]
            .map { try climb(id: $0) }
    }
}

private extension Climb {
    func recategorised(as category: String) -> Climb {
        Climb(
            id: id,
            name: name,
            commonName: commonName,
            city: city,
            country: country,
            continent: continent,
            latitude: latitude,
            longitude: longitude,
            totalHeightMeters: totalHeightMeters,
            totalHeightFeet: totalHeightFeet,
            realClimbableHeightMeters: realClimbableHeightMeters,
            realClimbableHeightFeet: realClimbableHeightFeet,
            totalSteps: totalSteps,
            realStairCount: realStairCount,
            calculatedFloors: calculatedFloors,
            category: category,
            tier: tier,
            tags: tags,
            funFact: funFact,
            sourceURL: sourceURL,
            imageSetVersion: imageSetVersion,
            releaseState: releaseState
        )
    }
}

/// Artwork for these climbs is not in Storage yet, so the shipped resolver returns no
/// URL and the placeholder is what a climber actually sees today.
private struct UnuploadedArtworkRepository: ClimbImageRepository {
    func resolveImageURL(for climb: Climb, variant: ClimbImageVariant) async -> URL? { nil }
}

// MARK: - Proof sheets

private struct ComingSoonPreviewProof: View {
    let climbs: [Climb]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Globe · tapping a 2026 World Tour pin")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            ForEach(climbs) { climb in
                VStack(alignment: .leading, spacing: 8) {
                    Text(climb.id)
                        .font(.montserratMedium(size: 11))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.5))

                    ClimbPreviewCardView(
                        summary: ClimbPreviewSummary(climb: climb, isCompleted: false),
                        onSelect: {},
                        onClose: {}
                    )
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

private struct StaircasePlaceholderProof: View {
    let staircase: Climb

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Artwork placeholder · category \"staircase\"")
                .font(.montserratBold(size: 19))
                .foregroundStyle(.white)

            Text("Until the images land in Storage, the category symbol is the artwork.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.white.opacity(0.62))

            HStack(alignment: .top, spacing: 16) {
                panel(variant: .hero, size: CGSize(width: 200, height: 150), label: "hero")
                VStack(spacing: 16) {
                    panel(variant: .card, size: CGSize(width: 130, height: 92), label: "card")
                    panel(variant: .thumb, size: CGSize(width: 64, height: 64), label: "thumb")
                }
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func panel(variant: ClimbImageVariant, size: CGSize, label: String) -> some View {
        VStack(spacing: 6) {
            ClimbArtworkView(
                climb: staircase,
                variant: variant,
                imageRepository: UnuploadedArtworkRepository()
            )
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(label)
                .font(.montserratMedium(size: 10))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct AdditionRosterProof: View {
    let climbs: [Climb]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Towerrunning World Tour 2026 · 29 venues added")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            Text("Each row shows the shipped race distance and the tier it derives.")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(.white.opacity(0.6))

            VStack(spacing: 5) {
                ForEach(climbs) { climb in
                    HStack(spacing: 10) {
                        Text(climb.name)
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: 250, alignment: .leading)

                        Text(climb.displayLocation)
                            .font(.montserratRegular(size: 11))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                            .frame(width: 190, alignment: .leading)

                        Text(
                            climb.realStairCount.map { "\($0.formatted()) steps" }
                                ?? "no published course distance"
                        )
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(
                            climb.realStairCount == nil
                                ? Color.ascendCaution
                                : .white.opacity(0.86)
                        )
                        .frame(width: 190, alignment: .leading)

                        Text(climb.tier.rawValue.uppercased())
                            .font(.montserratBold(size: 10))
                            .tracking(1)
                            .foregroundStyle(climb.tier.color)
                            .frame(width: 78, alignment: .leading)

                        Text("COMING SOON")
                            .font(.montserratBold(size: 9))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                }
            }
        }
        .padding(28)
        .frame(width: 930)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
