import Foundation
import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

/// Photographs the shipping public-profile achievements section in the three states a viewer can
/// land on, so a reviewer can see another climber's crown without running the app.
///
/// Drawn through a live `UIWindow` rather than `ImageRenderer`: the badge shelf is a horizontal
/// `ScrollView`, and `ImageRenderer` draws its content as blank.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct PublicProfileAchievementsVisualEvidenceTests {
    /// Three champion periods, two seconds, one third, and a long tail of ranked finishes.
    private static let champion = ProfileAchievementLadder(records: championRecords())

    private static func championRecords() -> [ProfileAchievementRecord] {
        var records: [ProfileAchievementRecord] = []

        for index in 1...3 {
            records.append(record(id: "champion-\(index)", type: .weeklyTop1, rank: 1))
        }
        for index in 1...2 {
            records.append(record(id: "second-\(index)", type: .monthlyTop3, rank: 2))
        }
        records.append(record(id: "third-1", type: .weeklyTop3, rank: 3))
        for index in 1...6 {
            records.append(record(id: "top-ten-\(index)", type: .weeklyTop10, rank: 4 + index))
        }
        for index in 1...29 {
            records.append(
                record(id: "top-hundred-\(index)", type: .weeklyTop100, rank: 20 + index)
            )
        }

        return records
    }

    private static func record(
        id: String,
        type: ProfileAchievementType,
        rank: Int
    ) -> ProfileAchievementRecord {
        ProfileAchievementRecord(
            id: id,
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: nil,
            periodStartAt: nil,
            periodEndAt: nil,
            earnedAt: Date(timeIntervalSince1970: 1_754_000_000),
            rank: rank,
            value: 12_000,
            valueUnit: "steps"
        )
    }

    @Test
    func loadedChampionProfileShowsTheirCrownAndBandCounts() throws {
        try Self.capture(
            name: "public-profile-achievements-loaded-champion",
            caption: "Another climber's public profile, snapshot loaded: their own crown and band counts",
            achievements: Self.champion,
            isOtherLoading: false
        )
    }

    @Test
    func loadedProfileWithNoAchievementsShowsNoSection() throws {
        try Self.capture(
            name: "public-profile-achievements-loaded-empty",
            caption: "Snapshot loaded, zero achievements: no heading, no shell, PROFILE runs straight into ALL-TIME",
            achievements: .empty,
            isOtherLoading: false
        )
    }

    @Test
    func loadingProfileShowsNothingUntilTheCountsResolve() throws {
        try Self.capture(
            name: "public-profile-achievements-loading",
            caption: "Snapshot still loading: nothing claimed for this climber until the counts resolve",
            achievements: Self.champion,
            isOtherLoading: true
        )
    }

    @Test
    func ownProfileShelfShowsFirstAscentsThenTheFullLadder() throws {
        try Self.captureOwnShelf(
            name: "own-profile-achievements-full-ladder",
            caption: "Own profile, records loaded: First Ascents, CHAMPION, #2, #3, TOP 10, TOP 100",
            achievements: Self.champion,
            held: [
                firstAscent(id: "eiffel", name: "Eiffel Tower"),
                firstAscent(id: "cn", name: "CN Tower")
            ]
        )
    }

    @Test
    func ownProfileShelfWithoutRecordsShowsOnlyTheBandsItCanProve() throws {
        try Self.captureOwnShelf(
            name: "own-profile-achievements-banded-fallback",
            caption: "Records missing, banded counters only: no #2 and no #3, because neither can be proven",
            achievements: ProfileAchievementLadder(
                bandedCounters: ProfileAchievementCounts(top1: 3, top3: 6, top10: 12, top100: 41)
            ),
            held: []
        )
    }

    /// The shelf scrolls horizontally, so a phone-width photograph cuts the tail off. This one
    /// is drawn wide enough to hold all six badges at once, which is the only frame that shows
    /// the ladder's order end to end and that TOP 10 / TOP 100 kept their framed tiles while
    /// the four cut-out badges stand free.
    @Test
    func theWholeOwnProfileLadderFitsInOneReviewableFrame() throws {
        try Self.captureOwnShelf(
            name: "own-profile-achievements-full-ladder-wide",
            caption: "Own profile, whole shelf unscrolled: First Ascents · CHAMPION · #2 · #3 free-standing, TOP 10 · TOP 100 still framed",
            achievements: Self.champion,
            held: [
                firstAscent(id: "eiffel", name: "Eiffel Tower"),
                firstAscent(id: "cn", name: "CN Tower")
            ],
            width: 680
        )
    }

    @Test
    func theWholeOtherClimberLadderFitsInOneReviewableFrame() throws {
        try Self.capture(
            name: "public-profile-achievements-full-ladder-wide",
            caption: "Another climber, whole shelf unscrolled: CHAMPION · #2 · #3 · TOP 10 · TOP 100, no TOP 3",
            achievements: Self.champion,
            isOtherLoading: false,
            width: 680
        )
    }

    /// The activation state stands the same cut-out flag beside its copy. It carries no circle
    /// clip and no stroke, because clipping a cut-out to a circle slices the flag off.
    @Test
    func theActivationStateStandsTheFirstAscentFlagFree() throws {
        try Self.captureOwnShelf(
            name: "own-profile-achievements-activation-empty",
            caption: "Nothing earned yet: the First Ascent flag stands free, no circle clip, no stroke",
            achievements: .empty,
            held: [],
            open: [firstAscent(id: "burj", name: "Burj Khalifa")]
        )
    }

    private func firstAscent(id: String, name: String) -> ProfileFirstAscentSummary {
        ProfileFirstAscentSummary(
            climbId: id,
            climbName: name,
            locationText: "Paris, France",
            tier: .gold,
            targetSteps: 1_665,
            kind: .held(claimedAt: Date(timeIntervalSince1970: 1_754_000_000))
        )
    }

    private static func captureOwnShelf(
        name: String,
        caption: String,
        achievements: ProfileAchievementLadder,
        held: [ProfileFirstAscentSummary],
        open: [ProfileFirstAscentSummary] = [],
        width: CGFloat = 402
    ) throws {
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            PrestigeSection(
                held: held,
                open: open,
                achievements: achievements,
                mode: .own,
                notificationState: ClimbDropNotificationState(
                    client: EvidenceNotificationStateClient(),
                    observesEnvironmentChanges: false
                )
            )
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(ProfileVisualStyle.background)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark
        let window = try makeWindow(host: host, width: width)
        defer { tearDown(window) }

        var fitted: CGFloat = 400
        for _ in 0..<10 {
            pump(window)
            fitted = host.sizeThatFits(
                in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            ).height
        }

        try write(draw(window, width: width, fittingHeight: fitted), name: name)
    }

    private static func capture(
        name: String,
        caption: String,
        achievements: ProfileAchievementLadder,
        isOtherLoading: Bool,
        width: CGFloat = 402
    ) throws {
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 30) {
                ProfileComparisonSection(title: "PROFILE") {
                    Text("Age · Height · Weight · Best streak")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                }

                PublicProfileAchievementsSection(
                    achievements: achievements,
                    isOtherLoading: isOtherLoading
                )

                ProfileComparisonSection(title: "ALL-TIME") {
                    Text("Steps · Climbs · Duration · Avg steps/min")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                }
            }
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(ProfileVisualStyle.background)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark
        let window = try makeWindow(host: host, width: width)
        defer { tearDown(window) }

        var fitted: CGFloat = 400
        for _ in 0..<10 {
            pump(window)
            fitted = host.sizeThatFits(
                in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            ).height
        }

        try write(draw(window, width: width, fittingHeight: fitted), name: name)
    }

    private static func makeWindow(
        host: UIHostingController<some View>,
        width: CGFloat
    ) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 500)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    private static func pump(_ window: UIWindow) {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    private static func draw(
        _ window: UIWindow,
        width: CGFloat,
        fittingHeight: CGFloat
    ) -> UIImage {
        window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fittingHeight))
        pump(window)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private static func tearDown(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }

    private static func write(_ image: UIImage, name: String) throws {
        let data = try #require(image.pngData(), "No PNG data for \(name)")
        let candidates = [
            ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"],
            NSTemporaryDirectory().appending("ascend-public-profile-evidence")
        ].compactMap { $0 }

        for directory in candidates {
            let url = URL(filePath: directory).appending(path: "\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: URL(filePath: directory),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
                print("ASCEND_EVIDENCE_PNG \(url.path)")
                return
            } catch {
                continue
            }
        }
        Issue.record("No writable evidence directory for \(name)")
    }
}

/// Keeps the shelf's `.task` off the simulator's real notification centre and off the
/// process-wide shared state: this suite photographs badges, it does not test prompting.
@MainActor
private final class EvidenceNotificationStateClient: ClimbDropNotificationStateClient {
    let isPreferenceEnabled = true

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestDuringOnboarding() async -> UNAuthorizationStatus { .authorized }
    func enable() async -> UNAuthorizationStatus { .authorized }
    func disable() async -> UNAuthorizationStatus { .authorized }
    func openSystemNotificationSettings() {}
}
