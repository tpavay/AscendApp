import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the three states the Email preference screen ships with:
/// on, off, and save-failed.
///
/// The screen is the front of a consent record, so what it says matters as much
/// as what it stores. This renders the real `EmailPreferencesContentView` in
/// each state
/// and reads the pixels back with Vision, asserting the switch label and the
/// broad-category paragraph are on screen, that the failure is visible when a
/// save does not land, and that the copy names no individual email type - the
/// point of writing it in categories was that adding an email never rewrites it.
///
/// The switch itself is a placeholder glyph in these renders: `ImageRenderer`
/// cannot rasterize the UIKit-backed control behind `Toggle`. Which way it is
/// pointing is held by `EmailPreferencesViewModelTests`, not by pixels.
@MainActor
struct EmailPreferencesScreenSnapshotTests {
    @Test
    func everyStateRendersTheSwitchAndItsParagraph() async throws {
        let onImage = try await renderScreen(state: .on)
        let offImage = try await renderScreen(state: .off)
        let failedImage = try await renderScreen(state: .saveFailed)

        let onText = try await recognizedText(in: onImage)
        let offText = try await recognizedText(in: offImage)
        let failedText = try await recognizedText(in: failedImage)

        for text in [onText, offText, failedText] {
            #expect(text.contains("ascend emails"))
            #expect(text.contains("when a climb drops"))
            #expect(text.contains("milestone worth marking"))
            #expect(text.contains("nothing daily"))
        }

        try writeEvidence(image: try await renderProofSheet(), named: "email-preferences-states.png")
    }

    @Test
    func aFailedSaveSaysSoOnTheScreen() async throws {
        // A preference that silently fails to save is the same class of bug as
        // a workout that silently fails to back up.
        let failedText = try await recognizedText(in: try await renderScreen(state: .saveFailed))
        let onText = try await recognizedText(in: try await renderScreen(state: .on))

        #expect(failedText.contains("couldn't save"))
        #expect(failedText.contains("check your connection"))
        // And it is not a permanent fixture of the screen.
        #expect(!onText.contains("couldn't save"))
    }

    @Test
    func theCopyNamesCategoriesRatherThanIndividualEmails() async throws {
        // Named so it survives the next email type. If any of these ever
        // appear, the paragraph has gone back to being a list to maintain.
        let text = try await recognizedText(in: try await renderScreen(state: .on))

        #expect(!text.contains("first ascent"))
        #expect(!text.contains("leaderboard"))
        #expect(!text.contains("rating"))
        #expect(!text.contains("weekly"))
    }

    @Test
    func theSwitchIsNotLabelledABlanketEmailSwitch() async throws {
        // The account-and-security line was deliberately cut: the switch is not
        // labelled as governing all mail, and the paragraph says what these
        // emails are, so naming the exclusion earns nothing.
        let text = try await recognizedText(in: try await renderScreen(state: .on))

        #expect(!text.contains("security"))
        #expect(!text.contains("always come through"))
    }

    // MARK: - States

    private enum ScreenState {
        case on
        case off
        case saveFailed
    }

    private func viewModel(for state: ScreenState) async -> EmailPreferencesViewModel {
        switch state {
        case .on:
            let model = EmailPreferencesViewModel(
                service: SnapshotEmailPreferencesService(storedConsent: .granted)
            )
            await model.load()
            return model
        case .off:
            let model = EmailPreferencesViewModel(
                service: SnapshotEmailPreferencesService(storedConsent: .declined)
            )
            await model.load()
            return model
        case .saveFailed:
            let service = SnapshotEmailPreferencesService(storedConsent: .granted)
            let model = EmailPreferencesViewModel(service: service)
            await model.load()
            await service.setSaveError(SnapshotError.offline)
            await model.setLifecycleEmailsEnabled(false)
            return model
        }
    }

    // MARK: - Rendering

    private func renderScreen(state: ScreenState) async throws -> UIImage {
        let renderer = ImageRenderer(
            content: EmailPreferencesContentView(viewModel: await viewModel(for: state))
                .frame(width: 350)
                .padding(20)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no image")
    }

    private func renderProofSheet() async throws -> UIImage {
        let renderer = ImageRenderer(
            content: EmailPreferencesProof(
                on: await viewModel(for: .on),
                off: await viewModel(for: .off),
                saveFailed: await viewModel(for: .saveFailed)
            )
        )
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no proof sheet")
    }

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: name))
        #expect(png.count > 5_000)
    }
}

private enum SnapshotError: Error {
    case offline
}

/// Reviewer-facing proof sheet: the three states side by side, as the board
/// shows them.
private struct EmailPreferencesProof: View {
    let on: EmailPreferencesViewModel
    let off: EmailPreferencesViewModel
    let saveFailed: EmailPreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Settings · Email")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            section("On", viewModel: on)
            section("Off", viewModel: off)
            section("Save failed", viewModel: saveFailed)
        }
        .padding(28)
        .frame(width: 446)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func section(
        _ title: String,
        viewModel: EmailPreferencesViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.2)

            EmailPreferencesContentView(viewModel: viewModel)
                .frame(width: 350)
                .padding(20)
                .background(Color.black)
        }
    }
}

private actor SnapshotEmailPreferencesService: EmailPreferencesProviding {
    private var storedConsent: LifecycleEmailConsent
    private var saveError: Error?

    init(storedConsent: LifecycleEmailConsent) {
        self.storedConsent = storedConsent
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        storedConsent
    }

    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws {
        if let saveError {
            throw saveError
        }

        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}
