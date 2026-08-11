import Foundation
import UIKit

@MainActor
final class RemoteFeatureFlagLifecycleCoordinator {
    private let notificationCenter: NotificationCenter
    private var foregroundObserver: NSObjectProtocol?
    private var onForeground: (@MainActor @Sendable () -> Void)?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func start(onForeground: @escaping @MainActor @Sendable () -> Void) {
        guard foregroundObserver == nil else { return }
        self.onForeground = onForeground

        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onForeground?()
            }
        }
    }

    func stop() {
        if let foregroundObserver {
            notificationCenter.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        onForeground = nil
    }
}
