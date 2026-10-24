import Foundation
import Testing
import UIKit
@testable import AscendApp

/// What stands down while a headphone session runs. Home's own behaviour under a session is
/// `HomeGlobeSheetEvidenceTests.theGlobeIsUnmountedWhileASessionRunsAndRemountedAfterIt`.
struct ActiveSessionFootprintPolicyTests {
    @Test("The globe stands down for the length of a session and comes back after it")
    func globeMounting() {
        #expect(ActiveSessionFootprintPolicy.mountsGlobe(sessionIsActive: false))
        #expect(!ActiveSessionFootprintPolicy.mountsGlobe(sessionIsActive: true))
    }

    @Test("Memory warnings are counted and shed the caches the app can rebuild")
    @MainActor
    func memoryWarningsAreCountedAndShed() {
        let center = NotificationCenter()
        let defaults = UserDefaults(suiteName: "memory-\(UUID().uuidString)")!
        let monitor = AppMemoryPressureMonitor(
            notificationCenter: center,
            diagnostics: AppDiagnosticsRecorder(userDefaults: defaults)
        )
        var shedCount = 0
        monitor.register { shedCount += 1 }
        let image = UIImage(systemName: "figure.stair.stepper")!
        let url = URL(string: "https://example.com/photo.heic")!
        ImageCache.shared.store(image, for: url)
        ClimbArtworkMemoryCache.shared.store(image, for: "artwork-key")

        monitor.handleMemoryWarning(at: Date(timeIntervalSince1970: 1_792_754_500))
        monitor.handleMemoryWarning(at: Date(timeIntervalSince1970: 1_792_754_530))

        #expect(monitor.warningCount == 2)
        #expect(monitor.lastWarningAt == Date(timeIntervalSince1970: 1_792_754_530))
        #expect(shedCount == 2)
        #expect(ImageCache.shared.image(for: url) == nil)
        #expect(ClimbArtworkMemoryCache.shared.image(for: "artwork-key") == nil)
    }
}
