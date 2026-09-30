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
        // Move the switch now; if the write fails, show whatever the server holds rather than
        // assuming the old value survived, since a failure can land after the write committed.
        isPublic = newValue
        defer { isUpdating = false }

        do {
            try await service.setIsPublic(newValue)
        } catch {
            errorMessage = (error as? ProfilePublicationError)?.errorDescription
                ?? "Couldn't save. Check your connection."
            isPublic = (try? await service.loadIsPublic()) ?? previous
        }
    }
}
