import Foundation
import Observation

/// Drives the switch on the Email preference screen.
@MainActor
@Observable
final class EmailPreferencesViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed
    }

    private(set) var loadState: LoadState = .loading
    /// Starts off, and stays off until the server says a climber said yes. A
    /// switch that shows on before the answer is known would be claiming a
    /// consent nobody has given.
    private(set) var consent: LifecycleEmailConsent = .undecided
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    private let service: EmailPreferencesProviding
    private var isLoading = false
    private var writeGeneration = 0

    init(service: EmailPreferencesProviding = EmailPreferencesService()) {
        self.service = service
    }

    /// What the switch shows. An unanswered question reads as off, which is
    /// exactly what the server will do with it.
    var isLifecycleEmailsEnabled: Bool {
        consent.allowsEmail
    }

    var isToggleDisabled: Bool {
        isUpdating || loadState != .ready
    }

    /// Reads the server value, which may have changed since the app last ran:
    /// an unsubscribe link in an email flips the same preference.
    ///
    /// Safe to call repeatedly. Once a value has been read, later reads are
    /// refreshes: they never take the screen back to loading or failed, since
    /// the value already on screen stays the best information available.
    func load() async {
        guard !isLoading, !isUpdating else { return }
        isLoading = true
        defer { isLoading = false }

        let hasKnownGoodValue = loadState == .ready
        if !hasKnownGoodValue {
            loadState = .loading
            errorMessage = nil
        }

        let generationAtReadStart = writeGeneration

        do {
            let serverValue = try await service.loadConsent()
            // A write that started mid-read still owns the value, and so does
            // one that both started and finished while this read was in
            // flight: either way the write is newer than what this read saw.
            guard !isUpdating, writeGeneration == generationAtReadStart else {
                return
            }

            consent = serverValue
            loadState = .ready
            errorMessage = nil
        } catch {
            guard !hasKnownGoodValue else { return }

            loadState = .failed
            errorMessage = "Couldn't load your email settings."
        }
    }

    func setLifecycleEmailsEnabled(_ isEnabled: Bool) async {
        let nextConsent = LifecycleEmailConsent(isGranted: isEnabled)
        guard !isUpdating, nextConsent != consent else { return }

        let previousConsent = consent
        isUpdating = true
        errorMessage = nil
        // Move the switch immediately, then put it back if the write fails, so
        // the control never shows a state the server did not accept.
        consent = nextConsent
        // A revert counts too: it settles the value just as a save does, so a
        // read that started before it is equally out of date.
        defer {
            writeGeneration += 1
            isUpdating = false
        }

        do {
            try await service.recordConsent(
                isGranted: isEnabled,
                source: .settings
            )
        } catch {
            consent = previousConsent
            errorMessage = "Couldn't save. Check your connection."
        }
    }
}
