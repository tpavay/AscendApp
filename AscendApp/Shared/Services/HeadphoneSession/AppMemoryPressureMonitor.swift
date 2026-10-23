import Foundation
import Observation
import UIKit

/// The app's one answer to `didReceiveMemoryWarning`.
///
/// iOS warns a process shortly before jetsam takes it, and until this existed Ascend did nothing
/// with the warning: the MapKit globe stayed alive under a pushed climb, three image caches kept
/// their contents, and a Live Climb was killed in the background a minute after the climber
/// opened Instagram (2026-10-23). Every warning now sheds what can be rebuilt and is counted,
/// so the next checkpoint can say how close the process came.
@MainActor
@Observable
final class AppMemoryPressureMonitor {
    static let shared = AppMemoryPressureMonitor(notificationCenter: .default)

    /// Warnings this process has received since it launched.
    private(set) var warningCount = 0
    /// Set when a warning arrives; the checkpoint that reads it and the recovery sheet that
    /// explains a death both want the answer to "did iOS warn first".
    private(set) var lastWarningAt: Date?

    private var shedders: [(id: UUID, shed: @MainActor () -> Void)] = []
    private var observer: (any NSObjectProtocol)?
    private let diagnostics: AppDiagnosticsRecorder

    init(
        notificationCenter: NotificationCenter,
        diagnostics: AppDiagnosticsRecorder = .shared
    ) {
        self.diagnostics = diagnostics
        observer = notificationCenter.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMemoryWarning()
            }
        }
        registerBuiltInShedders()
    }

    /// Registers work that frees memory the app can rebuild. Returns a token for `unregister`.
    @discardableResult
    func register(shedder: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        shedders.append((id, shedder))
        return id
    }

    func unregister(_ id: UUID) {
        shedders.removeAll { $0.id == id }
    }

    /// The notification handler, callable directly so a test can fire a warning without UIKit.
    func handleMemoryWarning(at now: Date = Date()) {
        warningCount += 1
        lastWarningAt = now
        shedders.forEach { $0.shed() }
        diagnostics.record(
            "memory_warning_received",
            level: .warning,
            details: [
                "warning_count": String(warningCount),
                "available_memory_mb": String(Int64(os_proc_available_memory()) / 1_048_576),
                "shedder_count": String(shedders.count)
            ]
        )
    }

    private func registerBuiltInShedders() {
        register { ImageCache.shared.clearAll() }
        register { ClimbArtworkMemoryCache.shared.removeAllImages() }
    }
}
