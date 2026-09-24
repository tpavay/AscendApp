import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for #600: every climb row on Home's browse sheet carries a "~N min" estimate
/// directly under its step count - the All Climbs list, a Browse by Steps category, and
/// search results - at iPhone SE width and at the standard width, with nothing clipped.
///
/// The rows are the shipping `ClimbBrowseSectionsView` / `ClimbSearchResultsView` fed the
/// bundled catalog and laid out with the sheet's 16 pt gutters. The row button replaces its
/// children's accessibility labels with the climb name and location, so the list-level
/// assertions read the glyphs (OCR); the layout assertions host the bare row, whose text
/// is on the accessibility tree with real frames.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbRowEstimatedTimeEvidenceTests {
    static let iPhoneSESize = CGSize(width: 375, height: 667)
    static let sheetGutter: CGFloat = 16

    /// A climber at 40 SPM - slower than the default - so personalized and default read differently.
    static let personalizedWorkouts = [
        Workout(duration: 25 * 60, steps: 1_000, floors: 62, source: .headphoneMotion),
    ]

    @Test(arguments: [("se", CGSize(width: 375, height: 667)), ("standard", CGSize(width: 402, height: 874))])
    func allClimbsListShowsAnEstimateUnderEveryStepCount(label: String, size: CGSize) async throws {
        let catalog = try ClimbService.shared.loadVisibleClimbs()
        for (variant, workouts) in [("personalized", Self.personalizedWorkouts), ("default", [Workout]())] {
            let spm = PersonalizedClimbPaceService.effectiveSPM(workouts: workouts)
            let viewModel = GlobeViewModel(leaderboardService: StubLiveReplayLeaderboardService())
            viewModel.visibleClimbs = catalog

            let firstRows = Array(
                viewModel.availableClimbs
                    .sorted { $0.referenceStepCount < $1.referenceStepCount }
                    .prefix(3)
            )
            try await RenderedScreen.host(
                sheet(
                    ClimbBrowseSectionsView(
                        viewModel: viewModel,
                        selectedStepTier: .constant(nil),
                        showsTodaysClimb: false,
                        effectiveSPM: spm,
                        onOpenClimb: { _, _ in },
                        onExpand: {}
                    )
                ),
                size: size
            ) { screen in
                let text = try await screen.recognizedText(scale: 3)
                for climb in firstRows {
                    let expected = ClimbEstimatedTimeFormatter.estimatedTimeText(for: climb.referenceStepCount, spm: spm)
                    #expect(
                        text.contains(expected.replacingOccurrences(of: "~", with: "").lowercased()),
                        "\(label)/\(variant): \(climb.name) should read \(expected); OCR read: \(text)"
                    )
                }
                #expect(!text.contains("~0 min") && !text.contains(" 0 min"))
                try screen.photograph(named: "climb-rows-all-climbs-\(variant)-\(label)")
            }
        }
    }

    @Test(arguments: [("se", CGSize(width: 375, height: 667)), ("standard", CGSize(width: 402, height: 874))])
    func browseByStepsCategoryAndSearchResultsShowTheEstimate(label: String, size: CGSize) async throws {
        let catalog = try ClimbService.shared.loadVisibleClimbs()
        let spm = PersonalizedClimbPaceService.effectiveSPM(workouts: Self.personalizedWorkouts)
        let viewModel = GlobeViewModel(leaderboardService: StubLiveReplayLeaderboardService())
        viewModel.visibleClimbs = catalog

        // The tallest tier present: the longest estimates, so the widest trailing column.
        let tallestTier = try #require(
            viewModel.availableClimbs.map { ClimbTier(steps: $0.referenceStepCount) }.max()
        )
        try await RenderedScreen.host(
            sheet(
                ClimbBrowseSectionsView(
                    viewModel: viewModel,
                    selectedStepTier: .constant(tallestTier),
                    showsTodaysClimb: false,
                    effectiveSPM: spm,
                    onOpenClimb: { _, _ in },
                    onExpand: {}
                )
            ),
            size: size
        ) { screen in
            let text = try await screen.recognizedText(scale: 3)
            #expect(text.contains("min") || text.contains("h"), "\(label): category rows OCR read: \(text)")
            try screen.photograph(named: "climb-rows-browse-by-steps-\(tallestTier.rawValue)-\(label)")
        }

        viewModel.searchQuery = "tower"
        #expect(!viewModel.searchSuggestions.isEmpty)
        try await RenderedScreen.host(
            sheet(ClimbSearchResultsView(viewModel: viewModel, effectiveSPM: spm, onOpenClimb: { _ in })),
            size: size
        ) { screen in
            let text = try await screen.recognizedText(scale: 3)
            let first = try #require(viewModel.searchSuggestions.first)
            let expected = ClimbEstimatedTimeFormatter.estimatedTimeText(for: first.referenceStepCount, spm: spm)
            #expect(
                text.contains(expected.replacingOccurrences(of: "~", with: "").lowercased()),
                "\(label): search row for \(first.name) should read \(expected); OCR read: \(text)"
            )
            try screen.photograph(named: "climb-rows-search-tower-\(label)")
        }
    }

    /// The estimate sits under the step count, inside the row, smaller than the count, and
    /// never pushes the trailing column off the row - checked for the tallest climb (longest
    /// estimate) and the longest name, at SE width, on the slowest plausible default pace.
    @Test
    func estimateSitsUnderTheStepCountWithoutClippingAtSEWidth() async throws {
        let catalog = try ClimbService.shared.loadVisibleClimbs().filter(\.isAvailable)
        let tallest = try #require(catalog.max { $0.referenceStepCount < $1.referenceStepCount })
        let longestName = try #require(catalog.max { $0.name.count < $1.name.count })
        let rowWidth = Self.iPhoneSESize.width - Self.sheetGutter * 2

        for (index, climb) in [tallest, longestName].enumerated() {
            for spm in [30, PersonalizedClimbPaceService.effectiveSPM(workouts: [])] {
                let estimate = ClimbEstimatedTimeFormatter.estimatedTimeText(for: climb.referenceStepCount, spm: spm)
                let steps = climb.referenceStepCount.formatted()
                try await RenderedScreen.host(
                    ClimbResultRowView(climb: climb, isCompleted: true, effectiveSPM: spm)
                        .frame(width: rowWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black),
                    size: CGSize(width: Self.iPhoneSESize.width, height: 160)
                ) { screen in
                    let texts = try await screen.texts { texts in
                        texts.contains { $0.text == estimate } && texts.contains { $0.text == steps }
                    }
                    let estimateFrame = try #require(texts.first { $0.text == estimate }?.frame, "\(climb.name): no \(estimate) in \(texts.map(\.text))")
                    let stepsFrame = try #require(texts.first { $0.text == steps }?.frame)
                    let rowMaxX = Self.sheetGutter + rowWidth

                    #expect(estimateFrame.minY >= stepsFrame.maxY, "\(climb.name): estimate is not under the step count")
                    #expect(estimateFrame.height < stepsFrame.height, "\(climb.name): estimate is not smaller than the step count")
                    #expect(estimateFrame.maxX <= rowMaxX, "\(climb.name): \(estimate) spills past the row (\(estimateFrame.maxX) > \(rowMaxX))")
                    #expect(estimateFrame.minX >= Self.sheetGutter)
                    #expect(estimate != "~0 min")
                    try screen.photograph(named: "climb-row-se-\(index == 0 ? "tallest" : "longest-name")-\(spm)spm")
                }
            }
        }
    }

    private func sheet(_ content: some View) -> some View {
        ScrollView(showsIndicators: false) {
            content.padding(.top, 20)
        }
        .padding(.horizontal, Self.sheetGutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }
}
