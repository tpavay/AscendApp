import Foundation

enum AppAccessRestoreState: CaseIterable, Equatable, Sendable {
    case idle
    case restoring
    case restored
    case noPurchasesFound
    case offline
    case timedOut
    case cancelled
    case failed

    init(outcome: AppAccessRestoreOutcome) {
        switch outcome {
        case .restored:
            self = .restored
        case .notFound:
            self = .noPurchasesFound
        case .failed(let error):
            switch error as? AppAccessRestoreError {
            case .offline:
                self = .offline
            case .timedOut:
                self = .timedOut
            case .cancelled:
                self = .cancelled
            case nil:
                self = .failed
            }
        }
    }

    func buttonTitle(isRevenueCatConfigured: Bool) -> String {
        guard isRevenueCatConfigured else { return "Restore Unavailable" }

        switch self {
        case .idle:
            return "Restore Purchases"
        case .restoring:
            return "Restoring..."
        case .restored:
            return "Restored"
        case .noPurchasesFound:
            // A conclusive negative is a finished operation, not a new label: the control keeps its
            // ordinary action name so the one found-nothing sentence lives in `statusMessage` alone.
            return "Restore Purchases"
        case .offline, .timedOut, .cancelled, .failed:
            return "Try Restore Again"
        }
    }

    var statusMessage: String? {
        switch self {
        case .idle, .restoring, .restored:
            return nil
        case .noPurchasesFound:
            return "No active Ascend subscription was found for this Apple ID."
        case .offline:
            return "Ascend is offline. Reconnect, then try Restore Purchases again."
        case .timedOut:
            return "Restore took too long. Check your connection, then try again."
        case .cancelled:
            return "Restore was cancelled. Try Restore Purchases again."
        case .failed:
            return "Apple could not finish the restore. Try again or contact support."
        }
    }

    func isButtonEnabled(isRevenueCatConfigured: Bool) -> Bool {
        isRevenueCatConfigured && self != .restoring
    }
}
