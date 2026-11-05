import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct ImportedClimbQuickEditFocusTests {
    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }

    private struct AlwaysMountedControl: View {
        @FocusState private var isFocused: Bool
        @State private var text = ""

        var body: some View {
            VStack(spacing: 24) {
                Button("Focus") { isFocused = true }
                TextField("field", text: $text)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
            }
            .padding(40)
        }
    }

    @Test("The method can see focus at all: a mounted field takes it from a button")
    func control() async throws {
        try await RenderedScreen.host(AlwaysMountedControl(), size: CGSize(width: 402, height: 400)) { screen in
            try await screen.settle()
            try activateAccessibilityElement(labelled: "Focus", in: screen.root)
            try await screen.settle(.turns(40))
            #expect(Self.firstResponder(in: screen.window) is UITextField)
        }
    }

    @Test("Tapping the steps tile on a climb with no steps opens its field")
    func theStepsTileTakesFocus() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 0.02, steps: nil, minutes: 25)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)

        try await RenderedScreen.host(
            ImportedClimbQuickEditSheet(workout: climb, importService: harness.service)
                .modelContainer(harness.container),
            size: CGSize(width: 402, height: 760)
        ) { screen in
            _ = try await screen.copy { $0.contains("remove this climb") }
            #expect(Self.firstResponder(in: screen.window) == nil)
            try activateAccessibilityElement(labelled: "Steps", in: screen.root)
            try await screen.settle(.turns(40))
            let field = try #require(Self.firstResponder(in: screen.window) as? UITextField, "tapping the tile must open the keyboard")
            #expect(field.keyboardType == .numberPad)

            field.insertText("4200")
            try await screen.settle(.turns(12))
            #expect(field.text == "4200")

            _ = field.resignFirstResponder()
            try await screen.settle(.turns(40))
            #expect(Self.firstResponder(in: screen.window) == nil)

            try activateAccessibilityElement(labelled: "Steps", in: screen.root)
            try await screen.settle(.turns(40))
            let reopened = try #require(Self.firstResponder(in: screen.window) as? UITextField, "the tile opens again after the field closes")
            #expect(reopened.text == "4200")
        }
    }
}
