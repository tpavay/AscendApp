import Foundation
import Testing
import UIKit
@testable import AscendApp

/// What may keep its weight while a headphone session runs. The lists are a contract: a view
/// joins the mounted set by a reviewed diff here, not by being added to Home.
struct ActiveSessionFootprintPolicyTests {
    @Test("The globe stands down for the length of a session and comes back after it")
    func globeMounting() {
        #expect(ActiveSessionFootprintPolicy.mountsGlobe(sessionIsActive: false))
        #expect(!ActiveSessionFootprintPolicy.mountsGlobe(sessionIsActive: true))
    }

    @Test("The root views allowed to stay mounted under an active session are exactly these")
    func mountedSetIsPinned() {
        #expect(ActiveSessionFootprintPolicy.rootViewsAllowedUnderActiveSession == [
            "HomeView",
            "GlobeEdgeOverlays",
            "ClimbCatalogStateOverlay",
            "MainTabBarView",
            "LiveClimbSessionView",
            "ActiveRoutineView",
            "ActiveHeadphoneWorkoutRecoveryView"
        ])
        #expect(ActiveSessionFootprintPolicy.rootViewsUnmountedUnderActiveSession == ["GlobeView"])
        #expect(ActiveSessionFootprintPolicy.rootViewsAllowedUnderActiveSession
            .isDisjoint(with: ActiveSessionFootprintPolicy.rootViewsUnmountedUnderActiveSession))
    }

    @Test("Home builds the globe only through the policy, and shows the placeholder otherwise")
    func homeReadsThePolicy() throws {
        let source = try String(contentsOf: Self.repositoryFile("AscendApp/Features/Home/Views/HomeView.swift"), encoding: .utf8)
        let globeConstructions = source.components(separatedBy: "GlobeView(").count - 1
        #expect(globeConstructions == 1, "one globe, built in one place")
        #expect(source.contains("if ActiveSessionFootprintPolicy.mountsGlobe(sessionIsActive: sessionRegistry.hasActiveSession) {"))
        #expect(source.contains(".accessibilityIdentifier(ActiveSessionFootprintPolicy.unmountedGlobeIdentifier)"))
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

    private static func repositoryFile(_ relativePath: String) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "AscendAppTests" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return url.appending(path: relativePath)
    }
}
