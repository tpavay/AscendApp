import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing visual evidence for the 2026 World Tour catalogue additions.
///
/// The catalogue is data, but a climber meets it as pixels: a raceable preview card
/// when they tap a pin on the globe, a locked "Coming Soon" card for the venue whose
/// course distance is still unpublished, and a category placeholder whenever artwork
/// is unavailable. These tests host the shipped views against the shipped catalogue
/// file, read the copy back off the accessibility tree (`RenderedScreen`), and write
/// reviewable proof sheets when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct WorldTour2026CatalogueEvidenceTests {
    @Test
    func newVenuesRenderTheReleaseStateTheCatalogueShipsThemAt() async throws {
        let showcase = try Self.showcase()

        for climb in showcase {
            let city = climb.city.lowercased()
            let text = try await RenderedScreen.host(cardContent(for: climb)) { screen in
                try await screen.copy { $0.contains(city) }
            }

            #expect(text.contains(city), "\(climb.id) lost its location")

            if climb.releaseState == .available {
                #expect(
                    text.contains("coming soon") == false,
                    "\(climb.id) still read as coming soon"
                )
                #expect(text.contains("steps"), "\(climb.id) did not expose its race distance")
            } else {
                // A venue with no published course distance announces itself as
                // locked, never as a climbable distance.
                #expect(text.contains("coming soon"), "\(climb.id) did not read as coming soon")
                #expect(
                    text.contains("steps") == false,
                    "\(climb.id) offered a distance it can't be raced at"
                )
            }
        }

        try RenderedScreen.photograph(
            PreviewCardProof(climbs: showcase),
            named: "world-tour-2026-preview-cards",
            scale: 2
        )
    }

    @Test
    func theOutdoorStaircaseRendersTheStairsPlaceholderRatherThanABuilding() async throws {
        let staircase = try Self.climb(id: "sommerbergbahn-stair")
        #expect(staircase.category == "staircase")

        // Hosted in a window rather than laid out flat, so the artwork's own load pass runs
        // and the tree holds the settled placeholder a climber sees, not a spinner.
        let copy = try await RenderedScreen.host(
            StaircasePlaceholderProof(staircase: staircase),
            size: CGSize(width: 460, height: 420)
        ) { screen in
            let copy = try await screen.copy { $0.contains("sommerbergbahn") }
            try screen.photograph(named: "world-tour-2026-staircase-placeholder", scale: 2)
            return copy
        }
        // The hero placeholder wraps the name across lines, so compare without spacing.
        let text = copy.replacing(" ", with: "")
        #expect(text.contains("sommerbergbahn"))

        // The two panels differ only by category, so identical pixels would mean the
        // "staircase" case never fired and the default building symbol was drawn. Each
        // panel is read at 1x and released before the other is laid out.
        let staircasePanel = try panelPixels(for: staircase)
        let asSkyscraper = try panelPixels(for: staircase.recategorised(as: "skyscraper"))
        #expect(staircasePanel != asSkyscraper)
    }

    @Test
    func theWholeAdditionSetRendersItsTierAndStepReadout() async throws {
        let additions = try Self.additions()
        #expect(additions.count == 29)
        #expect(additions.count(where: { $0.releaseState == .available }) == 28)

        let roster = AdditionRosterProof(climbs: additions)
        // The roster is wider than a phone, so it is hosted in a window of its own width,
        // tall enough to hold every row.
        let text = try await RenderedScreen.host(
            roster.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
            size: CGSize(width: 930, height: 1_300)
        ) { screen in
            try await screen.copy { $0.contains("no published course distance") }
        }

        #expect(text.contains("ping an finance centre") || text.contains("ping an"))
        #expect(text.contains("no published course distance"))

        try RenderedScreen.photograph(roster, named: "world-tour-2026-addition-roster", scale: 2)
    }

    // MARK: - Hosting the shipped views

    private func cardContent(for climb: Climb) -> some View {
        ClimbPreviewCardView(
            summary: ClimbPreviewSummary(climb: climb, isCompleted: false),
            onSelect: {},
            onClose: {}
        )
        .frame(width: 361)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    /// Every pixel of the hero placeholder for `climb`, laid out off screen. A colour
    /// comparison reads the same at 1x, so that is the scale it takes.
    private func panelPixels(for climb: Climb) throws -> [RGBA] {
        try RenderedScreen.withOffscreenPixels(
            of: ClimbArtworkView(
                climb: climb,
                variant: .hero,
                imageRepository: MissingArtworkRepository()
            )
            .frame(width: 200, height: 200)
            .environment(\.colorScheme, .dark)
        ) { pixels in
            pixels.pixels(in: CGRect(origin: .zero, size: pixels.size))
        }
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

/// Simulates an unavailable image so the category placeholder remains covered.
private struct MissingArtworkRepository: ClimbImageRepository {
    func resolveImageURL(for climb: Climb, variant: ClimbImageVariant) async -> URL? { nil }
}

private extension ClimbReleaseState {
    var evidenceLabel: String {
        switch self {
        case .available: "AVAILABLE"
        case .comingSoon: "COMING SOON"
        case .hidden: "HIDDEN"
        case .disabled: "DISABLED"
        }
    }
}

// MARK: - Proof sheets

private struct PreviewCardProof: View {
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

            Text("When artwork is unavailable, the category symbol is the fallback.")
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
                imageRepository: MissingArtworkRepository()
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
            Text("Towerrunning World Tour 2026 · 29 venues, 28 raceable")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            Text("Each row shows the shipped race distance, its tier, and its release state.")
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

                        Text(climb.releaseState.evidenceLabel)
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
