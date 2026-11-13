import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The Settings line for a running free week, read off a hosted screen: it states how much of the
/// week is left and is not a control, beside a Purchases row that still is one.
@MainActor
@Suite(.hostsAWindow, .serialized)
struct FreeWeekSettingsRowEvidenceTests {
    @Test(arguments: [(3, "Free trial, 3 days left"), (1, "Free trial, 1 day left")])
    func aRunningWeekIsAStatementNotAControl(daysLeft: Int, expected: String) async throws {
        let title = try #require(FreeWeekSettingsRow.title(daysLeft: daysLeft))
        #expect(title == expected)

        let size = CGSize(width: 390, height: 180)
        try await RenderedScreen.host(
            VStack(spacing: 0) {
                SettingsRow(option: SettingsOption(icon: .settingsManageSubscription, title: title))
                SettingsRow(option: SettingsOption(icon: .settingsManageSubscription, title: "Manage Subscription", action: {}))
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            let texts = try await screen.texts { found in
                found.contains { $0.text.contains(expected) } && found.contains { $0.text.contains("Manage Subscription") }
            }
            let freeWeek = try #require(texts.first { $0.text.contains(expected) })
            let manage = try #require(texts.first { $0.text.contains("Manage Subscription") })
            #expect(!freeWeek.traits.contains(.button), "The free-week row reads as a button")
            #expect(manage.traits.contains(.button), "Manage Subscription stopped being a button")
            try screen.photograph(named: "settings-free-week-row-\(daysLeft)-days")
        }
    }

    @Test
    func noRunningWeekMeansNoRow() {
        #expect(FreeWeekSettingsRow.title(daysLeft: nil) == nil)
        #expect(FreeWeekSettingsRow.title(daysLeft: 0) == nil)
    }
}
