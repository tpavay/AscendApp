import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Photographs the three surfaces that count a climb's field, so a reviewer can
/// read the approved presentation off the pixels rather than off the diff.
///
/// The three answer different questions about one climb on purpose - the live
/// race collapses a rival's repeat runs to their best, the static board keeps
/// every completion, the completion hero freezes a placement - and before this
/// change none of them said which population it counted.
///
/// Two of the three are the shipping views themselves: `LiveReplayLeaderboardPanel`
/// as `LiveClimbSessionView` configures it, and `LiveClimbCompletionSummaryView`
/// resolving its own `fieldPopulation` from the leaderboard context it was handed.
/// Climb Detail's third tab cannot be hosted - `ClimbDetailView` is a Firebase-auth
/// gated screen whose `.task` opens network work, the same reason
/// `ClimbLeaderboardTabVisualEvidenceTests` reproduces its page - so its selector
/// strip and page chrome are redrawn here from `ClimbDetailView.swift`, while the
/// line under review is the shipping `LiveReplayFieldSizeLine`.
///
/// Every assertion reads the rendered pixels back with Vision, so a caption that
/// never drew fails the test. PNGs land in `ASCEND_EVIDENCE_DIR` when set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveReplayFieldPopulationRenderEvidenceTests {
    private static let phoneSize = CGSize(width: 393, height: 852)
    /// The race HUD's board and Climb Detail's third tab occupy a panel, not a
    /// whole screen, so each is captured at the height its own content needs -
    /// which is what puts the pinned line where a climber actually reads it.
    private static let panelSize = CGSize(width: 393, height: 620)
    private static let pageSize = CGSize(width: 393, height: 700)

    /// Screen 1. The captain kept the title LEADERBOARD and rejected renaming it;
    /// the panel says which field it ranks on a bottom-pinned centred line instead.
    @Test
    func liveRacePanelKeepsItsTitleAndNamesTheClimbersItRanks() async throws {
        let image = try raceHUD(field: LiveReplayFieldSize(population: .climbers, count: 27))
        let text = try await recognizedText(in: image)

        #expect(text.contains("leaderboard"))
        #expect(text.contains("27 climbers"))
        #expect(!text.contains("the field"))
        #expect(!text.contains("best run per climber"))
        #expect(appearsBefore("leaderboard", "27 climbers", in: text))

        try writeEvidence(image: image, named: "field-population-1-live-race-panel.png")
    }

    /// The same panel with nothing on hand that measures its field - an open Just
    /// Climb, or a landmark race before the server's count lands - states no total
    /// rather than counting the rows on screen.
    @Test
    func aPanelWithNoSubstantiatedFieldStatesNoTotal() async throws {
        let image = try raceHUD(field: nil)
        let text = try await recognizedText(in: image)

        #expect(text.contains("leaderboard"))
        #expect(!text.contains("climbers"))
        #expect(!text.contains("completions"))

        try writeEvidence(image: image, named: "field-population-2-live-race-panel-no-field.png")
    }

    /// Screen 2. Climb Detail's third tab, renamed LEADERBOARD -> ALL TIMES, with
    /// the identical line and one noun swapped.
    @Test
    func climbDetailsThirdTabReadsAllTimesAndCountsCompletions() async throws {
        let image = try screenshot(of: AllTimesTabProof(), size: Self.pageSize)
        let text = try await recognizedText(in: image)

        #expect(text.contains("all times"))
        #expect(text.contains("60 completions"))
        #expect(!text.contains("leaderboard"))
        #expect(appearsBefore("all times", "60 completions", in: text))

        try writeEvidence(image: image, named: "field-population-3-climb-detail-all-times.png")
    }

    /// Screen 3, rendered by the shipping completion summary: a landmark climb's
    /// context collapses repeat finishers, so the hero's field line names climbers.
    @Test
    func theCompletionHeroNamesTheClimberFieldItWasRankedAgainst() async throws {
        let image = try renderCompletionSummary(
            context: .liveClimb(climbId: "cn-tower", targetSteps: 2_579)
        )
        let text = try await recognizedText(in: image)

        #expect(text.contains("fastest of 27 climbers"))
        #expect(!text.contains("fastest of 27 completions"))

        try writeEvidence(image: image, named: "field-population-4-completion-hero-climbers.png")
    }

    /// The noun follows the replay context rather than being hardcoded. An open
    /// Just Climb has no step target to collapse on and races every completed
    /// attempt, so the same hero, same rank, same total says completions.
    @Test
    func theSameHeroSaysCompletionsWhereTheContextRacesAttempts() async throws {
        let image = try renderCompletionSummary(context: .justClimbGlobal(targetSteps: 2_579))
        let text = try await recognizedText(in: image)

        #expect(text.contains("fastest of 27 completions"))
        #expect(!text.contains("fastest of 27 climbers"))

        try writeEvidence(image: image, named: "field-population-5-completion-hero-completions.png")
    }

    /// One sheet a reviewer can read end to end: the three approved screens as
    /// rendered screenshots, side by side with the totals that used to read as a
    /// contradiction.
    @Test
    func proofSheetShowsAllThreeSurfacesTogether() async throws {
        let panels: [(String, String, UIImage)] = [
            (
                "Live race panel - during a Live Climb",
                "Title stays LEADERBOARD. One row per climber, best run only, and the field it ranks pinned at the bottom.",
                try raceHUD(field: LiveReplayFieldSize(population: .climbers, count: 27))
            ),
            (
                "Climb Detail, third tab - the same climb",
                "Renamed LEADERBOARD -> ALL TIMES. Every completion kept, so the same climb honestly shows a different total.",
                try screenshot(of: AllTimesTabProof(), size: Self.pageSize)
            ),
            (
                "Completion summary - the rank you just froze",
                "FASTEST OF 27 CLIMBERS. The noun comes from the replay context, so an open Just Climb says COMPLETIONS instead.",
                try crop(
                    try renderCompletionSummary(
                        context: .liveClimb(climbId: "cn-tower", targetSteps: 2_579)
                    ),
                    to: CGRect(x: 0, y: 40, width: Self.phoneSize.width, height: 320)
                )
            )
        ]

        let sheet = try #require(
            {
                let renderer = ImageRenderer(content: FieldPopulationProofSheet(panels: panels))
                renderer.scale = 2
                return renderer.uiImage
            }(),
            "ImageRenderer produced no proof sheet"
        )

        try writeEvidence(image: sheet, named: "field-population-0-proof-sheet.png")
    }

    /// The race HUD's board, with the empty navigation strip the hosting stack
    /// leaves above it trimmed off - the session screen has no bar there.
    private func raceHUD(field: LiveReplayFieldSize?) throws -> UIImage {
        let full = try screenshot(of: RaceHUDProof(field: field), size: Self.panelSize)
        return try crop(
            full,
            to: CGRect(
                x: 0,
                y: 60,
                width: Self.panelSize.width,
                height: Self.panelSize.height - 60
            )
        )
    }

    // MARK: - Rendering the shipping completion summary

    private func renderCompletionSummary(
        context: LiveReplayLeaderboardContext
    ) throws -> UIImage {
        let screen = LiveClimbCompletionSummaryView(
            climb: nil,
            workout: Workout(
                name: "CN Tower Live Climb",
                duration: 1_908,
                steps: 2_579,
                floors: 144,
                caloriesBurned: 486,
                source: .headphoneMotion
            ),
            leaderboardRank: 4,
            leaderboardTotal: 27,
            leaderboardRankBasis: .atCompletion,
            leaderboardContext: context,
            completedDetailOverride: "LIVE CLIMB COMPLETE",
            onDone: { _ in }
        )
        .modelContainer(try #require(Self.container, "The evidence suite needs a model container"))

        return try screenshot(of: screen, size: Self.phoneSize)
    }

    /// Held for the process: the summary carries a `@Query`, and SwiftUI keeps
    /// observing SwiftData for a beat after the host is torn down.
    private static let container: ModelContainer? = try? ModelContainer(
        for: AscendLocalStore.schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    // MARK: - Capture

    private func screenshot(of view: some View, size: CGSize) throws -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark

        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.rootViewController = controller
        window.isHidden = false

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    private func crop(_ image: UIImage, to rect: CGRect) throws -> UIImage {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        let scale = image.scale
        let scaled = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let cropped = try #require(cgImage.cropping(to: scaled), "Crop fell outside the image")
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
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

    private func appearsBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let firstRange = text.range(of: first),
              let secondRange = text.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        #expect(png.count > 5_000)

        let candidates = [
            ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"],
            NSTemporaryDirectory().appending("ascend-field-population-evidence")
        ].compactMap { $0 }

        for directory in candidates {
            do {
                try FileManager.default.createDirectory(
                    at: URL(filePath: directory),
                    withIntermediateDirectories: true
                )
                let url = URL(filePath: directory).appending(path: name)
                try png.write(to: url)
                print("ASCEND_EVIDENCE_PNG \(url.path())")
                return
            } catch {
                continue
            }
        }

        Issue.record("No writable evidence directory for \(name)")
    }

    // MARK: - Fixtures

    static func raceRows() -> [ModeratedReplayLeaderboardRow] {
        [
            row(id: "1", rank: 1, name: "Marcus T.", steps: 1_910),
            row(id: "2", rank: 2, name: "Priya S.", steps: 1_742),
            row(id: "3", rank: 3, name: "Tyler P.", steps: 1_610, isCurrentUser: true),
            row(id: "4", rank: 4, name: "Dana R.", steps: 1_498),
            row(id: "5", rank: 5, name: "Owen B.", steps: 1_330)
        ]
    }

    private static func row(
        id: String,
        rank: Int,
        name: String,
        steps: Int,
        isCurrentUser: Bool = false
    ) -> ModeratedReplayLeaderboardRow {
        CrossUserIdentityAdapter.replayRow(
            LiveReplayLeaderboardRow(
                id: id,
                rank: rank,
                displayName: name,
                avatarToken: String(name.prefix(1)),
                photoURL: nil,
                stepsAtBucket: steps,
                finalSteps: 2_579,
                deltaFromUser: 0,
                isCurrentUser: isCurrentUser,
                isPersonalBest: isCurrentUser,
                completionDurationSeconds: 1_800 + Double(rank) * 40,
                userId: "user-\(id)"
            ),
            blockedUserIds: [],
            isBlockListHydrated: true
        )
    }
}

/// The live race HUD's board, configured exactly as `LiveClimbSessionView.leaderboardPanel`
/// does: no filter control, accent tint, dark scheme. The panel itself is shipping code.
private struct RaceHUDProof: View {
    let field: LiveReplayFieldSize?

    var body: some View {
        // A rival's row is a `NavigationLink` into their profile, so the board
        // needs a stack around it or every row but the climber's own draws
        // disabled-dim - which is not what the screen looks like.
        NavigationStack {
            LiveReplayLeaderboardPanel(
                rows: LiveReplayFieldPopulationRenderEvidenceTests.raceRows(),
                progressScaleSteps: 2_579,
                targetStepGoal: 2_579,
                progress: 0.62,
                currentUserPhotoURL: nil,
                fetchFailed: false,
                field: field,
                tint: .accent,
                effectiveColorScheme: .dark,
                showsFilter: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Climb Detail's third tab. The selector strip and page chrome are redrawn from
/// `ClimbDetailView.swift` - same titles, same tokens, same order - and the line
/// beneath the rows is the shipping `LiveReplayFieldSizeLine` the screen draws.
private struct AllTimesTabProof: View {
    private let titles = ["OVERVIEW", "HISTORY", "ALL TIMES"]
    private let selectedPage = 2
    private let gold = Color(hex: "F3D76B")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("CN TOWER")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)

            selector

            VStack(alignment: .leading, spacing: 18) {
                Text("First Ascent: John Smith · Aug 11, 2026")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(gold)

                VStack(spacing: 8) {
                    ForEach(LiveReplayFieldPopulationRenderEvidenceTests.raceRows()) { row in
                        completionRow(row)
                    }
                }

                LiveReplayFieldSizeLine(
                    field: LiveReplayFieldSize(population: .completions, count: 60),
                    effectiveColorScheme: .dark
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private var selector: some View {
        HStack(spacing: 4) {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index])
                    .font(.montserratBold(size: 11))
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(index == selectedPage ? .black : .white.opacity(0.64))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if index == selectedPage {
                            Capsule(style: .continuous)
                                .fill(ClimbTier.gold.color)
                        }
                    }
            }
        }
        .padding(4)
        .background(.white.opacity(0.055), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func completionRow(_ row: ModeratedReplayLeaderboardRow) -> some View {
        HStack(spacing: 12) {
            Text("#\(row.rank ?? 0)")
                .font(.montserratBold(size: 15))
                .foregroundStyle(row.rank == 1 ? gold : .white.opacity(0.62))
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()

            Text(row.identity.avatarToken)
                .font(.montserratBold(size: 13))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color(hex: "8C5A36")))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.identity.displayName)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)

                    if row.isCurrentUser {
                        Text("YOU")
                            .font(.montserratBold(size: 9))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(Color.accent))
                    }
                }

                Text("2,579 steps")
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(durationText(for: row))
                .font(.montserratBold(size: 16))
                .foregroundStyle(row.isCurrentUser ? .accent : .white)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func durationText(for row: ModeratedReplayLeaderboardRow) -> String {
        let seconds = Int((row.completionDurationSeconds ?? 0).rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Reviewer-facing sheet. Every panel image is a crop of a real screenshot; only
/// the captions are drawn here.
private struct FieldPopulationProofSheet: View {
    let panels: [(String, String, UIImage)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Three boards, three populations, each one named")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                Text("One climb. The live race ranks 27 climbers on their best run, the static board keeps all 60 completions, and the frozen rank states the field it was measured against. Every total now says which population it counts.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(panels.enumerated()), id: \.offset) { _, panel in
                VStack(alignment: .leading, spacing: 8) {
                    Text(panel.0)
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.accent)

                    Text(panel.1)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)

                    Image(uiImage: panel.2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 393)
                }
            }
        }
        .padding(28)
        .frame(width: 449)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
