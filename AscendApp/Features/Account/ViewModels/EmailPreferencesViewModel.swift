import Foundation
import Observation

/// Drives the email preference toggle in notification settings.
@MainActor
@Observable
final class EmailPreferencesViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed
    }

    private(set) var loadState: LoadState = .loading
    private(set) var isLifecycleEmailsEnabled = true
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    private let service: EmailPreferencesProviding
    private var isLoading = false
    private var writeGeneration = 0

    init(service: EmailPreferencesProviding = EmailPreferencesService()) {
        self.service = service
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
            let serverValue = try await service.loadLifecycleEmailsEnabled()
            // A write that started mid-read still owns the value, and so does
            // one that both started and finished while this read was in
            // flight: either way the write is newer than what this read saw.
            guard !isUpdating, writeGeneration == generationAtReadStart else {
                return
            }

            isLifecycleEmailsEnabled = serverValue
            loadState = .ready
            errorMessage = nil
        } catch {
            guard !hasKnownGoodValue else { return }

            loadState = .failed
            errorMessage = "Couldn't load your email settings."
        }
    }

    func setLifecycleEmailsEnabled(_ isEnabled: Bool) async {
        guard !isUpdating, isEnabled != isLifecycleEmailsEnabled else { return }

        let previousValue = isLifecycleEmailsEnabled
        isUpdating = true
        errorMessage = nil
        // Move the switch immediately, then put it back if the write fails, so
        // the control never shows a state the server did not accept.
        isLifecycleEmailsEnabled = isEnabled
        // A revert counts too: it settles the value just as a save does, so a
        // read that started before it is equally out of date.
        defer {
            writeGeneration += 1
            isUpdating = false
        }

        do {
            try await service.setLifecycleEmailsEnabled(isEnabled)
        } catch {
            isLifecycleEmailsEnabled = previousValue
            errorMessage = "Couldn't save that. Check your connection."
        }
    }
}
