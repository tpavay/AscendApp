import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Photographs the shipping public-profile achievements section in the three states a viewer can
/// land on, so a reviewer can see another climber's crown without running the app.
///
/// Drawn through a live `UIWindow` rather than `ImageRenderer`: the badge shelf is a horizontal
/// `ScrollView`, and `ImageRenderer` draws its content as blank.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct PublicProfileAchievementsVisualEvidenceTests {
    private static let champion = ProfileAchievementCounts(top1: 3, top3: 5, top10: 12, top100: 41)

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
            achievements: .zero,
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

    private static func capture(
        name: String,
        caption: String,
        achievements: ProfileAchievementCounts,
        isOtherLoading: Bool
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
        .frame(width: 402, alignment: .topLeading)
        .background(ProfileVisualStyle.background)
        .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark
        let window = try makeWindow(host: host)
        defer { tearDown(window) }

        var fitted: CGFloat = 400
        for _ in 0..<10 {
            pump(window)
            fitted = host.sizeThatFits(
                in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude)
            ).height
        }

        try write(draw(window, fittingHeight: fitted), name: name)
    }

    private static func makeWindow(host: UIHostingController<some View>) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 500)
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

    private static func draw(_ window: UIWindow, fittingHeight: CGFloat) -> UIImage {
        window.frame = CGRect(x: 0, y: 0, width: 402, height: ceil(fittingHeight))
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
