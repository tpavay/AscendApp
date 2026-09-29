import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Where "Show my heart rate on my profile" lives and what it says: the Privacy section of
/// Settings, and the screen that row opens, in both positions. Proven off the accessibility tree;
/// photographed when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct HeartRateVisibilityEvidenceTests {
    @Test
    func settingsListsTheSwitchInThePrivacySectionAboveBlockedClimbers() async throws {
        let size = CGSize(width: 402, height: 1_500)
        let controller = UIHostingController(
            rootView: NavigationStack {
                AccountView()
                    .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        try await RenderedScreen.host(controller, size: size) { screen in
            let text = try await screen.copy { $0.contains("blocked climbers") }
            try screen.photograph(named: "settings-privacy-heart-rate-row")

            let privacy = try #require(text.range(of: "privacy", options: .backwards))
            let heartRate = try #require(
                text.range(of: "heart rate"),
                "Settings never drew the heart rate row. Read: \(text)"
            )
            let blocked = try #require(text.range(of: "blocked climbers"))
            #expect(privacy.lowerBound < heartRate.lowerBound)
            #expect(heartRate.lowerBound < blocked.lowerBound)
        }
    }

    @Test
    func theSwitchScreenReadsOnByDefault() async throws {
        try await photographSwitch(storedIsPublic: true, named: "heart-rate-visibility-on")
    }

    @Test
    func theSwitchScreenReadsOffOnceHidden() async throws {
        try await photographSwitch(storedIsPublic: false, named: "heart-rate-visibility-off")
    }

    private func photographSwitch(storedIsPublic: Bool, named name: String) async throws {
        let viewModel = HeartRateVisibilityViewModel(
            service: HeartRateVisibilityViewModelTests.StubService(stored: storedIsPublic)
        )
        await viewModel.load()
        #expect(viewModel.isPublic == storedIsPublic)

        let size = CGSize(width: 402, height: 520)
        let controller = UIHostingController(
            rootView: NavigationStack {
                ScrollView {
                    HeartRateVisibilityContentView(viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }
                .themedBackground()
                .navigationTitle("Heart Rate")
                .navigationBarTitleDisplayMode(.inline)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        try await RenderedScreen.host(controller, size: size) { screen in
            let text = try await screen.copy { $0.contains("show my heart rate on my profile") }
            #expect(text.contains("you still see your own"))
            try screen.photograph(named: name)
        }
    }
}
