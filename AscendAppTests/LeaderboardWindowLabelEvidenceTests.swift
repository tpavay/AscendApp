import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence that every board names the window it covers.
///
/// The captain photographed three Steps tabs on 2026-08-01: a populated WEEKLY board
/// and a MONTHLY board reading "No entries yet." Unlabelled, that pair reads as data
/// loss. It is not: the week of Mon Jul 27 runs into Aug 2, so on the 1st it carries
/// July steps the freshly opened August board cannot. These images are rendered from
/// the shipping `LeaderboardView` - header, tab filters, window label and empty state -
/// so the label and the copy are photographed exactly where a climber meets them.
///
/// Signed out, `setupAndLoad` returns before it loads anything, which is what puts the
/// board in the empty state the monthly tab was actually in.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary
/// directory otherwise; the path is logged either way. Nothing reads them back - these
/// are evidence, not golden-image assertions.
@MainActor
struct LeaderboardWindowLabelEvidenceTests {
    @Test
    func weeklyBoardNamesTheWeekItCovers() async throws {
        let period = LeaderboardTimeFrame.weekly.currentPeriod()
        // A dated range, never a bare "This week" - the dates are the whole point.
        #expect(period.windowLabel.contains("-"))

        try await snapshot(
            leaderboard(initialTimeFrame: .weekly),
            named: "leaderboard-window-label-weekly",
            height: 620
        )
    }

    /// The board the captain read as broken. Early in August it is young, not empty of
    /// data that should be there, and the label plus the empty-state subject say so.
    @Test
    func monthlyBoardNamesTheMonthAndStatesItIsEmpty() async throws {
        let period = LeaderboardTimeFrame.monthly.currentPeriod()
        #expect(period.windowSubject == period.windowLabel)

        try await snapshot(
            leaderboard(initialTimeFrame: .monthly),
            named: "leaderboard-window-label-monthly-empty",
            height: 620
        )
    }

    @Test
    func yearlyBoardNamesTheYearItCovers() async throws {
        try await snapshot(
            leaderboard(initialTimeFrame: .yearly),
            named: "leaderboard-window-label-yearly",
            height: 620
        )
    }

    // MARK: - Fixtures

    private func leaderboard(initialTimeFrame: LeaderboardTimeFrame) throws -> some View {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return NavigationStack {
            LeaderboardView(initialTimeFrame: initialTimeFrame, viewSource: .tab)
        }
        .environment(AuthenticationViewModel())
        .environment(ModerationStore.shared)
        .environment(NetworkConnectivityService.shared)
        .environment(TabRouter())
        .modelContainer(container)
    }

    // MARK: - Rendering

    /// Hosts the view in a real window so the scroll content lays out, then captures
    /// what is on screen.
    private func snapshot(
        _ view: some View,
        named name: String,
        height: CGFloat
    ) async throws {
        let size = CGSize(width: 390, height: height)
        let controller = UIHostingController(
            rootView: view
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .black

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<12 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered leaderboard window evidence: \(url.path())")
    }
}
