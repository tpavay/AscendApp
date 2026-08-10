import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct PublicProfileAchievementRenderingTests {
    @Test
    func presentAchievementsRenderTheOtherClimbersExactBandCounts() async throws {
        let achievements = ProfileAchievementCounts(
            top1: 2,
            top3: 4,
            top10: 7,
            top100: 9
        )
        let elements = try await renderedElements(
            achievements: achievements,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("CHAMPION, 2"))
        #expect(labels.contains("TOP 3, 4"))
        #expect(labels.contains("TOP 10, 7"))
        #expect(labels.contains("TOP 100, 9"))
    }

    @Test
    func absentAchievementsRenderNoPublicAchievementShell() async throws {
        let elements = try await renderedElements(
            achievements: .zero,
            isOtherLoading: false
        )
        let labels = elements.compactMap(\.accessibilityLabel)

        #expect(labels.contains("Public profile test host"))
        #expect(labels.contains("Achievements") == false)
        #expect(labels.contains { $0.hasPrefix("CHAMPION,") } == false)
        #expect(labels.contains { $0.hasPrefix("TOP ") } == false)
    }

    @Test
    func loadingAchievementsRenderTheSharedSkeletonState() async throws {
        let elements = try await renderedElements(
            achievements: .zero,
            isOtherLoading: true
        )
        let loadingElement = try #require(
            elements.first { $0.accessibilityLabel == "Achievements" }
        )

        #expect(loadingElement.accessibilityValue == "Loading")
    }

    @Test
    func crownAndPrestigeTokensProduceReviewablePixels() throws {
        let achievements = ProfileAchievementCounts(
            top1: 2,
            top3: 4,
            top10: 7,
            top100: 9
        )
        let tokens = ProfilePrestigeToken.leaderboardTokens(for: achievements)
        let crown = try #require(tokens.first)
        let renderer = ImageRenderer(
            content: VStack(alignment: .leading, spacing: 24) {
                Text("CROWN SIZE CHECK")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)

                HStack(alignment: .bottom, spacing: 30) {
                    VStack(spacing: 8) {
                        Image("LeaderboardCrown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text("16 PT")
                    }

                    VStack(spacing: 8) {
                        Image("LeaderboardCrown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                        Text("30 PT")
                    }

                    ProfilePrestigeBadgeView(token: crown, imageSize: 46)
                    ProfilePrestigeBadgeView(token: crown, imageSize: 54)
                }
                .font(.montserratSemiBold(size: 9))
                .foregroundStyle(ProfileVisualStyle.secondaryText)

                Text("UNCHANGED FRAMED TOKENS")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)

                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(tokens.dropFirst())) { token in
                        ProfilePrestigeBadgeView(token: token, imageSize: 54)
                    }
                }
            }
            .padding(20)
            .frame(width: 420, height: 410, alignment: .topLeading)
            .background(ProfileVisualStyle.background)
        )
        renderer.scale = 3

        let image = try #require(renderer.uiImage)
        let png = try #require(image.pngData())
        let url = URL.temporaryDirectory.appending(path: "crown-and-prestige-tokens.png")
        try png.write(to: url, options: .atomic)

        print("ASCEND_EVIDENCE_PNG \(url.path)")
    }

    private func renderedElements(
        achievements: ProfileAchievementCounts,
        isOtherLoading: Bool
    ) async throws -> [NSObject] {
        try await withAccessibilityAutomation {
            let size = CGSize(width: 402, height: 300)
            let controller = UIHostingController(
                rootView: VStack(alignment: .leading, spacing: 30) {
                    Text("Public profile test host")
                        .accessibilityLabel("Public profile test host")

                    PublicProfileAchievementsSection(
                        achievements: achievements,
                        achievementRecords: [],
                        isOtherLoading: isOtherLoading
                    )
                }
                .padding(20)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(ProfileVisualStyle.background)
            )
            controller.overrideUserInterfaceStyle = .dark
            controller.view.frame = CGRect(origin: .zero, size: size)

            let scene = try #require(
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first,
                "The hosted public profile needs an active window scene"
            )
            let window = UIWindow(windowScene: scene)
            window.frame = controller.view.frame
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            return try await settledAccessibilityElements(
                under: controller.view,
                until: { elements in
                    elements.contains {
                        $0.accessibilityLabel == "Public profile test host"
                    }
                }
            )
        }
    }
}
