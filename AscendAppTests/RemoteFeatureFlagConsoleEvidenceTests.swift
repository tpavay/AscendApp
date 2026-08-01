import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the operator-facing half of the kill switches: the **Remote Flags** console
/// an operator opens to confirm a switch they just threw in the Firebase console actually landed on
/// the build in front of them.
///
/// Every frame below is the *shipping* `RemoteFeatureFlagsView`, hosted in a real `UIWindow` and
/// photographed without being rebuilt between frames - the same live view instance repaints as
/// values arrive, which is the claim being demonstrated: a switch lands without a relaunch.
///
/// The backend is scripted rather than live so the three states are deterministic, but everything
/// downstream of it is real: `RemoteFeatureFlagService` resolves the values, publishes them to
/// `RemoteFeatureFlagStore.shared`, and posts `.remoteFeatureFlagsDidChange`, and the view is
/// listening for exactly that.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary directory
/// otherwise; the path is logged either way. Nothing reads them back - these are evidence, not
/// golden-image assertions.
@MainActor
@Suite(.serialized)
struct RemoteFeatureFlagConsoleEvidenceTests {
    @Test
    func theRemoteFlagsConsoleShowsAKillSwitchLandingWithoutARelaunch() async throws {
        // The test host boots the real app, so the Firebase-backed shared service is already
        // running against a live project. Let its in-flight fetch finish and then stop it, so
        // nothing races the scripted values below.
        await RemoteFeatureFlagService.shared.refreshAndWait()
        RemoteFeatureFlagService.shared.teardown()
        defer { RemoteFeatureFlagStore.shared.apply(.shippedDefaults) }
        RemoteFeatureFlagStore.shared.apply(.shippedDefaults)

        // Deliberately writes into the shared store, because the shipping view reads that and
        // nothing else.
        let backend = ScriptedRemoteConfigBackend(
            fetchResult: .failure(ScriptedRemoteConfigBackend.Offline())
        )
        let service = RemoteFeatureFlagService(source: backend)

        let host = hostConsole()
        defer { host.window.isHidden = true }

        // 1. Cold launch with no answer from the backend - the documented fail-open posture.
        service.configure()
        await service.refreshAndWait()
        try await settle(host)
        for flag in RemoteFeatureFlag.allCases {
            #expect(RemoteFeatureFlagStore.shared.snapshot.source(of: flag) == .shippedDefault)
            #expect(RemoteFeatureFlagStore.shared.isEnabled(flag) == true)
        }
        try capture(host, named: "remote-flags-1-cold-launch-no-answer")

        // 2. The published template lands. Same values, but now the console can prove they came
        //    from the server rather than from the binary.
        backend.setFetchResult(.success(allFlags(enabled: true)))
        await service.refreshAndWait()
        try await settle(host)
        for flag in RemoteFeatureFlag.allCases {
            #expect(RemoteFeatureFlagStore.shared.snapshot.source(of: flag) == .remote)
        }
        try capture(host, named: "remote-flags-2-template-published")

        // 3. An operator throws one switch in the Firebase console. It arrives over the real-time
        //    connection, on the running app, with no relaunch and no new submission.
        var thrown = allFlags(enabled: true)
        thrown[RemoteFeatureFlag.workoutMediaUploads.key] = false
        backend.emitUpdate(thrown)
        _ = await waitUntilFlags {
            RemoteFeatureFlagStore.shared.isEnabled(.workoutMediaUploads) == false
        }
        try await settle(host)

        #expect(RemoteFeatureFlagStore.shared.isEnabled(.workoutMediaUploads) == false)
        #expect(RemoteFeatureFlagStore.shared.snapshot.source(of: .workoutMediaUploads) == .remote)
        #expect(RemoteFeatureFlagStore.shared.snapshot.disabledFlagKeys == ["workout_media_uploads_enabled"])
        // The switch is surgical: throwing one must not take the other six down with it.
        for flag in RemoteFeatureFlag.allCases where flag != .workoutMediaUploads {
            #expect(RemoteFeatureFlagStore.shared.isEnabled(flag) == true)
        }
        try capture(host, named: "remote-flags-3-media-uploads-killed")

        // 4. Restoring the parameter puts the path back, again without a release.
        backend.emitUpdate(allFlags(enabled: true))
        _ = await waitUntilFlags {
            RemoteFeatureFlagStore.shared.isEnabled(.workoutMediaUploads)
        }
        try await settle(host)
        #expect(RemoteFeatureFlagStore.shared.snapshot.disabledFlagKeys.isEmpty)
        try capture(host, named: "remote-flags-4-switch-restored")

        service.teardown()
    }

    // MARK: - Helpers

    private func allFlags(enabled: Bool) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: RemoteFeatureFlag.allCases.map { ($0.key, enabled) })
    }

    private struct Host {
        let window: UIWindow
        let controller: UIViewController
    }

    private func hostConsole() -> Host {
        let size = CGSize(width: 393, height: 852)
        let controller = UIHostingController(
            rootView: NavigationStack {
                RemoteFeatureFlagsView()
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .black

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return Host(window: window, controller: controller)
    }

    private func settle(_ host: Host) async throws {
        for _ in 0..<10 {
            host.controller.view.setNeedsLayout()
            host.controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func capture(_ host: Host, named name: String) throws {
        let bounds = host.controller.view.bounds
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            host.controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered Remote Flags evidence: \(url.path())")
    }
}

/// A scripted stand-in for the Remote Config backend, lock-guarded so `emitUpdate` reaches the
/// service's listener synchronously the way the real SDK callback does.
private final class ScriptedRemoteConfigBackend: RemoteFeatureFlagSource, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private var storedFetchResult: Result<[String: Bool], any Error>
    private var onUpdate: (@Sendable ([String: Bool]) -> Void)?

    init(fetchResult: Result<[String: Bool], any Error>) {
        storedFetchResult = fetchResult
    }

    func setFetchResult(_ result: Result<[String: Bool], any Error>) {
        lock.withLock { storedFetchResult = result }
    }

    func emitUpdate(_ values: [String: Bool]) {
        let handler = lock.withLock { onUpdate }
        handler?(values)
    }

    func fetchAndActivate() async throws -> [String: Bool] {
        try lock.withLock { storedFetchResult }.get()
    }

    func activatedValues() -> [String: Bool] { [:] }

    func startListening(onUpdate: @escaping @Sendable ([String: Bool]) -> Void) {
        lock.withLock { self.onUpdate = onUpdate }
    }

    func stopListening() {
        lock.withLock { onUpdate = nil }
    }
}

@MainActor
private func waitUntilFlags(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
