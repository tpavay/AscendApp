import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Hosts the three surfaces that count a climb's field, so a reviewer can read
/// the approved presentation off the photograph rather than off the diff.
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
/// Every assertion reads the hosted screen's copy off the accessibility tree
/// (`RenderedScreen`), so a caption that never made it on screen fails the test.
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set and are not taken otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveReplayFieldPopulationRenderEvidenceTests {
    static let phoneSize = CGSize(width: 393, height: 852)
    /// The race HUD's board and Climb Detail's third tab occupy a panel, not a
    /// whole screen, so each is hosted at the height its own content needs -
    /// which is what puts the pinned line where a climber actually reads it.
    static let panelSize = CGSize(width: 393, height: 620)
    static let pageSize = CGSize(width: 393, height: 700)

    /// Screen 1. The captain kept the title LEADERBOARD and rejected renaming it;
    /// the panel says which field it ranks on a bottom-pinned centred line instead.
    @Test
    func liveRacePanelKeepsItsTitleAndNamesTheClimbersItRanks() async throws {
        try await RenderedScreen.host(
            RaceHUDProof(field: LiveReplayFieldSize(population: .climbers, count: 27)),
            size: Self.panelSize
        ) { screen in
            let text = try await screen.copy { $0.contains("27 climbers") }

            #expect(text.contains("leaderboard"))
            #expect(text.contains("27 climbers"))
            #expect(!text.contains("the field"))
            #expect(!text.contains("best run per climber"))
            #expect(appearsBefore("leaderboard", "27 climbers", in: text))

            try screen.photograph(named: "field-population-1-live-race-panel")
        }
    }

    /// The same panel with nothing on hand that measures its field - an open Just
    /// Climb, or a landmark race before the server's count lands - states no total
    /// rather than counting the rows on screen.
    @Test
    func aPanelWithNoSubstantiatedFieldStatesNoTotal() async throws {
        try await RenderedScreen.host(RaceHUDProof(field: nil), size: Self.panelSize) { screen in
            let text = try await screen.copy { $0.contains("leaderboard") }

            #expect(text.contains("leaderboard"))
            #expect(!text.contains("climbers"))
            #expect(!text.contains("completions"))

            try screen.photograph(named: "field-population-2-live-race-panel-no-field")
        }
    }

    /// Screen 2. Climb Detail's third tab, renamed LEADERBOARD -> ALL TIMES, with
    /// the identical line and one noun swapped.
    @Test
    func climbDetailsThirdTabReadsAllTimesAndCountsCompletions() async throws {
        try await RenderedScreen.host(AllTimesTabProof(), size: Self.pageSize) { screen in
            let text = try await screen.copy { $0.contains("60 completions") }

            #expect(text.contains("all times"))
            #expect(text.contains("60 completions"))
            #expect(!text.contains("leaderboard"))
            #expect(appearsBefore("all times", "60 completions", in: text))

            try screen.photograph(named: "field-population-3-climb-detail-all-times")
        }
    }

    /// Screen 3, rendered by the shipping completion summary: a landmark climb's
    /// context collapses repeat finishers, so the hero's field line names climbers.
    @Test
    func theCompletionHeroNamesTheClimberFieldItWasRankedAgainst() async throws {
        try await RenderedScreen.host(
            try completionSummary(context: .liveClimb(climbId: "cn-tower", targetSteps: 2_579)),
            size: Self.phoneSize
        ) { screen in
            let text = try await screen.copy { $0.contains("fastest of 27") }

            #expect(text.contains("fastest of 27 climbers"))
            #expect(!text.contains("fastest of 27 completions"))

            try screen.photograph(named: "field-population-4-completion-hero-climbers")
        }
    }

    /// The noun follows the replay context rather than being hardcoded. An open
    /// Just Climb has no step target to collapse on and races every completed
    /// attempt, so the same hero, same rank, same total says completions.
    @Test
    func theSameHeroSaysCompletionsWhereTheContextRacesAttempts() async throws {
        try await RenderedScreen.host(
            try completionSummary(context: .justClimbGlobal(targetSteps: 2_579)),
            size: Self.phoneSize
        ) { screen in
            let text = try await screen.copy { $0.contains("fastest of 27") }

            #expect(text.contains("fastest of 27 completions"))
            #expect(!text.contains("fastest of 27 climbers"))

            try screen.photograph(named: "field-population-5-completion-hero-completions")
        }
    }

    /// One sheet a reviewer can read end to end: the three approved screens, live,
    /// side by side with the totals that used to read as a contradiction. Hosted
    /// only when a photograph is being written; the populations it names are
    /// pinned from the contexts either way.
    @Test
    func proofSheetShowsAllThreeSurfacesTogether() async throws {
        let raced = LiveReplayLeaderboardContext.liveClimb(climbId: "cn-tower", targetSteps: 2_579)
        let open = LiveReplayLeaderboardContext.justClimbGlobal(targetSteps: 2_579)
        #expect([raced.type.fieldPopulation, open.type.fieldPopulation] == [.climbers, .completions])

        guard RenderedScreen.isPhotographing else { return }

        try await RenderedScreen.host(
            FieldPopulationProofSheet(summary: try completionSummary(context: raced)),
            size: FieldPopulationProofSheet<EmptyView>.size
        ) { screen in
            try screen.photograph(named: "field-population-0-proof-sheet")
        }
    }

    // MARK: - The shipping completion summary

    private func completionSummary(context: LiveReplayLeaderboardContext) throws -> some View {
        LiveClimbCompletionSummaryView(
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
            moment: .retrospective,
            completedDetailOverride: "LIVE CLIMB COMPLETE",
            onDone: { _ in }
        )
        .modelContainer(try #require(Self.container, "The evidence suite needs a model container"))
    }

    /// Held for the process: the summary carries a `@Query`, and SwiftUI keeps
    /// observing SwiftData for a beat after the host is torn down.
    private static let container: ModelContainer? = try? ModelContainer(
        for: AscendLocalStore.schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    // MARK: - Reading the copy back

    private func appearsBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let firstRange = text.range(of: first),
              let secondRange = text.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
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

/// Reviewer-facing sheet. Every panel is the live surface itself, hosted at the
/// size its own test hosts it and cropped to the part a climber reads; only the
/// captions are drawn here. Built only to be photographed.
private struct FieldPopulationProofSheet<Summary: View>: View {
    private typealias Sizes = LiveReplayFieldPopulationRenderEvidenceTests

    /// Tall enough for the three panels and their captions; the rest stays black.
    static var size: CGSize { CGSize(width: 449, height: 2_000) }

    let summary: Summary

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

            panel(
                "Live race panel - during a Live Climb",
                "Title stays LEADERBOARD. One row per climber, best run only, and the field it ranks pinned at the bottom."
            ) {
                // The empty navigation strip the hosting stack leaves above the board is
                // trimmed off - the session screen has no bar there.
                cropped(
                    RaceHUDProof(field: LiveReplayFieldSize(population: .climbers, count: 27)),
                    hostedAt: Sizes.panelSize,
                    top: 60,
                    height: Sizes.panelSize.height - 60
                )
            }

            panel(
                "Climb Detail, third tab - the same climb",
                "Renamed LEADERBOARD -> ALL TIMES. Every completion kept, so the same climb honestly shows a different total."
            ) {
                AllTimesTabProof()
                    .frame(width: Sizes.pageSize.width, height: Sizes.pageSize.height)
            }

            panel(
                "Completion summary - the rank you just froze",
                "FASTEST OF 27 CLIMBERS. The noun comes from the replay context, so an open Just Climb says COMPLETIONS instead."
            ) {
                cropped(summary, hostedAt: Sizes.phoneSize, top: 40, height: 320)
            }
        }
        .padding(28)
        .frame(width: Self.size.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func panel(_ title: String, _ caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.montserratBold(size: 13))
                .foregroundStyle(.accent)

            Text(caption)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
    }

    /// `content` laid out at the size its own test hosts it, showing only the band
    /// `height` tall that starts `top` points down.
    private func cropped(_ content: some View, hostedAt size: CGSize, top: CGFloat, height: CGFloat) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .offset(y: -top)
            .frame(width: size.width, height: height, alignment: .top)
            .clipped()
    }
}
