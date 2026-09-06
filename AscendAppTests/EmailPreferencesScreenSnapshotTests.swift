import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the three states the Email preference screen ships with:
/// on, off, and save-failed.
///
/// The screen is the front of a consent record, so what it says matters as much
/// as what it stores. This hosts the real `EmailPreferencesContentView` in each
/// state and reads its on-screen copy back off the accessibility tree
/// (`RenderedScreen`), asserting the switch label and the broad-category
/// paragraph are on screen, that the failure is visible when a save does not
/// land, and that the copy names no individual email type - the point of writing
/// it in categories was that adding an email never rewrites it.
///
/// Which way the switch is pointing is held by `EmailPreferencesViewModelTests`,
/// not by this screen.
@MainActor
@Suite(.hostsAWindow)
struct EmailPreferencesScreenSnapshotTests {
    @Test
    func everyStateRendersTheSwitchAndItsParagraph() async throws {
        let onText = try await screenCopy(state: .on)
        let offText = try await screenCopy(state: .off)
        let failedText = try await screenCopy(state: .saveFailed)

        for text in [onText, offText, failedText] {
            #expect(text.contains("ascend emails"))
            #expect(text.contains("when a climb drops"))
            #expect(text.contains("when you hit a milestone"))
            #expect(text.contains("never daily"))
        }

        try await photographProofSheet()
    }

    @Test
    func aFailedSaveSaysSoOnTheScreen() async throws {
        // A preference that silently fails to save is the same class of bug as
        // a workout that silently fails to back up.
        let failedText = try await screenCopy(state: .saveFailed)
        let onText = try await screenCopy(state: .on)

        #expect(failedText.contains("couldn't save"))
        #expect(failedText.contains("check your connection"))
        // And it is not a permanent fixture of the screen.
        #expect(!onText.contains("couldn't save"))
    }

    @Test
    func theCopyNamesCategoriesRatherThanIndividualEmails() async throws {
        // Named so it survives the next email type. If any of these ever
        // appear, the paragraph has gone back to being a list to maintain.
        let text = try await screenCopy(state: .on)

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
        let text = try await screenCopy(state: .on)

        #expect(!text.contains("security"))
        #expect(!text.contains("always come through"))
        // Nor may it claim the reverse. Account and transactional mail never
        // enters this queue, so promising the switch governs it would put the
        // screen at odds with the privacy policy.
        #expect(!text.contains("account"))
    }

    @Test
    func aFailedLoadOffersAWayBack() async throws {
        // The switch is disabled while the stored answer is unknown, so without
        // a retry the one screen a climber can record an answer on is dead
        // until they leave and come back.
        //
        // Read by OCR, not off the tree: the failure row is one button whose
        // accessibility label ("Retry loading your email settings") replaces
        // its visible copy, and this test's contract is what the climber sees.
        let text = try await RenderedScreen.host(screenContent(state: .loadFailed)) { screen in
            try await screen.recognizedText(scale: 2)
        }

        #expect(text.contains("couldn't load your email settings"))
        #expect(text.contains("retry"))
    }

    // MARK: - States

    private enum ScreenState {
        case on
        case off
        case saveFailed
        case loadFailed
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
        case .loadFailed:
            let service = SnapshotEmailPreferencesService(storedConsent: .granted)
            await service.setLoadError(SnapshotError.offline)
            let model = EmailPreferencesViewModel(service: service)
            await model.load()
            return model
        }
    }

    // MARK: - Reading the hosted screen back

    /// The screen's on-screen copy in `state`, lowercased, off the accessibility tree.
    private func screenCopy(state: ScreenState) async throws -> String {
        try await RenderedScreen.host(screenContent(state: state)) { screen in
            try await screen.copy()
        }
    }

    private func screenContent(state: ScreenState) async -> some View {
        EmailPreferencesContentView(viewModel: await viewModel(for: state))
            .frame(width: 350)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }

    /// The reviewer-facing proof sheet, written only when `ASCEND_EVIDENCE_DIR` is set.
    private func photographProofSheet() async throws {
        guard RenderedScreen.isPhotographing else { return }
        try RenderedScreen.photograph(
            EmailPreferencesProof(
                on: await viewModel(for: .on),
                off: await viewModel(for: .off),
                saveFailed: await viewModel(for: .saveFailed)
            ),
            named: "email-preferences-states"
        )
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
    private var loadError: Error?

    init(storedConsent: LifecycleEmailConsent) {
        self.storedConsent = storedConsent
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        if let loadError {
            throw loadError
        }

        return storedConsent
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
