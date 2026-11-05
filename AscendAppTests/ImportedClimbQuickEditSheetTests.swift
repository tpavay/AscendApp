import PhotosUI
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct ImportedClimbQuickEditSheetTests {
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
            let tile = try #require(accessibilityElements(under: screen.root).first { $0.accessibilityLabel == "Steps" })
            #expect(tile.accessibilityValue == "Not recorded")

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
            _ = reopened.resignFirstResponder()
            try await screen.settle(.turns(40))
            let filled = try #require(accessibilityElements(under: screen.root).first { $0.accessibilityLabel == "Steps" })
            #expect(filled.accessibilityValue == "4,200", "VoiceOver reads the count the tile draws")
        }
    }

    private static func element(_ label: String, in screen: HostedScreen) -> NSObject? {
        accessibilityElements(under: screen.root).first { $0.accessibilityLabel?.contains(label) == true }
    }

    @Test("A climb already holding the maximum says so, and its Photo tile opens nothing")
    func aFullClimbsPhotoTileIsDisabled() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 0.02, steps: 3_000, minutes: 30)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)
        climb.photos = (0..<SelectedMediaPreparationService.maximumMediaCount).map { index in
            Photo(url: URL(string: "https://example.com/\(index).jpg")!)
        }
        try harness.context.save()

        try await RenderedScreen.host(
            ImportedClimbQuickEditSheet(workout: climb, importService: harness.service)
                .modelContainer(harness.container),
            size: CGSize(width: 402, height: 760)
        ) { screen in
            _ = try await screen.copy { $0.contains("3 of 3 photos") }
            let tile = try #require(Self.element("3 of 3 photos", in: screen))
            #expect(tile.accessibilityTraits.contains(.notEnabled))

            _ = tile.accessibilityActivate()
            try await screen.settle(.turns(40))
            #expect(Self.element("Add photos", in: screen) == nil)
        }

        climb.photos.removeLast()
        try harness.context.save()
        try await RenderedScreen.host(
            ImportedClimbQuickEditSheet(workout: climb, importService: harness.service)
                .modelContainer(harness.container),
            size: CGSize(width: 402, height: 760)
        ) { screen in
            let copy = try await screen.copy { $0.contains("photo") }
            #expect(!copy.contains("of 3 photos"), "\(copy)")
            let tile = try #require(Self.element("Photo", in: screen))
            #expect(!tile.accessibilityTraits.contains(.notEnabled), "a climb with room still takes one")
        }
    }

    @Test("While Done uploads, Remove this climb cannot run and the sheet takes no more edits")
    func theSheetLocksDuringASave() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 0.02, steps: 3_000, minutes: 30)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)

        let upload = HeldUpload()
        let viewModel = Self.savingViewModel(for: climb, upload: upload)

        try await RenderedScreen.host(
            ImportedClimbQuickEditSheet(viewModel: viewModel, importService: harness.service)
                .modelContainer(harness.container),
            size: CGSize(width: 402, height: 760)
        ) { screen in
            _ = try await screen.copy { $0.contains("remove this climb") }
            let idle = try #require(Self.element("Remove this climb", in: screen))
            #expect(!idle.accessibilityTraits.contains(.notEnabled))

            let saving = Task { await viewModel.finish(modelContext: harness.context) }
            try await upload.waitUntilHeld()
            try await screen.settle(.turns(40))

            let remove = try #require(Self.element("Remove this climb", in: screen))
            #expect(remove.accessibilityTraits.contains(.notEnabled))
            let steps = try #require(Self.element("Steps", in: screen))
            #expect(steps.accessibilityTraits.contains(.notEnabled))
            let effort = try #require(Self.element("Effort", in: screen))
            #expect(effort.accessibilityTraits.contains(.notEnabled))

            _ = remove.accessibilityActivate()
            try await screen.settle(.turns(40))
            #expect(try harness.climbs().count == 1, "the climb is still there for the save to land on")

            upload.release()
            #expect(await saving.value)
            #expect(climb.photos.count == 1)
        }
    }

    @Test("While Done uploads, the sheet cannot be swiped away")
    func theSheetCannotBeSwipedAwayDuringASave() async throws {
        let harness = try AppleHealthImportHarness(referenceNow: Date())
        harness.addWorkout(daysAgo: 0.02, steps: 3_000, minutes: 30)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)
        let upload = HeldUpload()
        let viewModel = Self.savingViewModel(for: climb, upload: upload)

        try await RenderedScreen.host(
            Color.black.sheet(isPresented: .constant(true)) {
                ImportedClimbQuickEditSheet(viewModel: viewModel, importService: harness.service)
            }
            .modelContainer(harness.container),
            size: CGSize(width: 402, height: 760)
        ) { screen in
            func presented() -> UIViewController? { screen.window.rootViewController?.presentedViewController }
            let deadline = ContinuousClock.now + .seconds(5)
            while presented() == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try await screen.settle(.turns(40))
            let sheet = try #require(presented())
            #expect(!sheet.isModalInPresentation, "at rest a swipe closes it")

            let saving = Task { await viewModel.finish(modelContext: harness.context) }
            try await upload.waitUntilHeld()
            try await screen.settle(.turns(40))
            #expect(sheet.isModalInPresentation, "a swipe would hide a failed save")

            upload.release()
            #expect(await saving.value)
            try await screen.settle(.turns(40))
            #expect(!sheet.isModalInPresentation)
            sheet.dismiss(animated: false)
            try await screen.settle(.turns(12))
        }
    }

    private static func savingViewModel(for climb: Workout, upload: HeldUpload) -> ImportedClimbQuickEditViewModel {
        let viewModel = ImportedClimbQuickEditViewModel(
            workout: climb,
            uploadMedia: { _ in await upload.hold() },
            applyUpdate: { _, _, _ in }
        )
        viewModel.selectedPhotos = [
            SelectedPhotoItem(
                pickerItem: PhotosPickerItem(itemIdentifier: "picked"),
                image: Image(systemName: "photo"),
                localIdentifier: "picked"
            )
        ]
        return viewModel
    }

    /// Holds an upload open so a test can read the sheet while the save is in flight.
    @MainActor
    private final class HeldUpload {
        private var continuation: CheckedContinuation<[Photo], Never>?

        func hold() async -> [Photo] {
            await withCheckedContinuation { continuation = $0 }
        }

        func waitUntilHeld() async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while continuation == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(continuation != nil, "the save never reached its upload")
        }

        func release() {
            continuation?.resume(returning: [Photo(url: URL(string: "https://example.com/picked.jpg")!)])
            continuation = nil
        }
    }
}
