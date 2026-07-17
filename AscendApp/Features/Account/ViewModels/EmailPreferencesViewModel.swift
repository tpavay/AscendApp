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

    init(service: EmailPreferencesProviding = EmailPreferencesService()) {
        self.service = service
    }

    var isToggleDisabled: Bool {
        isUpdating || loadState != .ready
    }

    /// Reads the server value, which may have changed since the app last ran:
    /// an unsubscribe link in an email flips the same preference.
    func load() async {
        loadState = .loading
        errorMessage = nil

        do {
            isLifecycleEmailsEnabled = try await service
                .loadLifecycleEmailsEnabled()
            loadState = .ready
        } catch {
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
        defer { isUpdating = false }

        do {
            try await service.setLifecycleEmailsEnabled(isEnabled)
        } catch {
            isLifecycleEmailsEnabled = previousValue
            errorMessage = "Couldn't save that. Check your connection."
        }
    }
}
