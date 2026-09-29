import Foundation
import Observation

/// Drives the "Show my heart rate on my profile" switch.
@MainActor
@Observable
final class HeartRateVisibilityViewModel {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed
    }

    private(set) var loadState: LoadState = .loading
    /// Shows the default until the stored choice is read, and the switch stays disabled until
    /// then, so it never offers to change a value nobody has seen.
    private(set) var isPublic = ProfileHeartRateVisibility.defaultIsPublic
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    private let service: any HeartRateVisibilityProviding

    init(service: any HeartRateVisibilityProviding) {
        self.service = service
    }

    var isToggleDisabled: Bool {
        isUpdating || loadState != .ready
    }

    func load() async {
        guard !isUpdating else { return }
        let hasKnownGoodValue = loadState == .ready
        if !hasKnownGoodValue {
            loadState = .loading
            errorMessage = nil
        }

        do {
            let stored = try await service.loadIsPublic()
            guard !isUpdating else { return }
            isPublic = stored
            loadState = .ready
            errorMessage = nil
        } catch {
            guard !hasKnownGoodValue else { return }
            loadState = .failed
            errorMessage = "Couldn't load your heart rate setting."
        }
    }

    func setIsPublic(_ newValue: Bool) async {
        guard !isUpdating, loadState == .ready, newValue != isPublic else { return }

        let previous = isPublic
        isUpdating = true
        errorMessage = nil
        // Move the switch now and put it back if the write fails, so it never shows a choice the
        // server did not record.
        isPublic = newValue
        defer { isUpdating = false }

        do {
            try await service.setIsPublic(newValue)
        } catch {
            isPublic = previous
            errorMessage = (error as? ProfilePublicationError)?.errorDescription
                ?? "Couldn't save. Check your connection."
        }
    }
}
