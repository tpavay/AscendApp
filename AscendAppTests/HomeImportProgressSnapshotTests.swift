import Foundation
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Visual evidence for the user-facing half of ASCEND-IOS-1K: Home renders immediately and says
/// what it is doing instead of freezing behind a whole-store scan.
///
/// Two states are proved, because they are the two a user actually lands in:
/// - auto-import off (the shipped default): the header draws right away and the notification bell
///   carries the pending count, so nothing is silently withheld;
/// - auto-import on: the slim `HomeImportProgressBar` states the condition and the remaining
///   session count while the backfill lands a workout at a time underneath it.
///
/// The header row is reproduced exactly as `HomeView.body` composes it (wordmark, spacer, real
/// `NotificationBellView`) because `HomeView` itself cannot be flattened into a snapshot - it owns
/// a `ScrollView`, SwiftData queries and injected observables. The strip and the bell are the real
/// shipping views, not stand-ins.
///
/// Captured through a hosted `UIWindow` rather than `ImageRenderer`: the strip's determinate
/// `ProgressView(.linear)` is a UIKit-backed control, and `ImageRenderer` draws its track without
/// the proportional fill - which is exactly the pixel this evidence is about.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct HomeImportProgressSnapshotTests {
    private static let sheetSize = CGSize(width: 430, height: 620)

    @Test
    func rendersTheBellCountAndTheBackfillProgressStrip() throws {
        let image = try screenshot(of: HomeImportStatesProof())
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "home-import-progress-states.png")
        try png.write(to: url)
        print("ASCEND-IOS-1K home import states snapshot -> \(url.path())")

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(png.count > 5_000)
    }

    private func screenshot(of view: some View) throws -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: Self.sheetSize)

        // A window with no scene is never handed to the render server and `drawHierarchy` then
        // captures an empty surface, so borrow the test host's own scene.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.sheetSize))
        window.frame = CGRect(origin: .zero, size: Self.sheetSize)
        window.overrideUserInterfaceStyle = .dark

        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.rootViewController = controller
        // Visible but never key: the capture is synchronous and the scene is shared with the other
        // window-hosting evidence suites.
        window.isHidden = false
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // SwiftUI commits its first frame on the next runloop turn; without this the window draws
        // empty.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(size: Self.sheetSize, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}

private struct HomeImportStatesProof: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            panel(
                caption: "Auto-import off (default)",
                note: "Home draws immediately; the bell carries the pending count."
            ) {
                header(pendingImports: 12)
            }

            panel(
                caption: "Auto-import on - backfill landing",
                note: "The strip states the condition and what is left."
            ) {
                VStack(spacing: 0) {
                    header(pendingImports: 0)
                    HomeImportProgressBar(remainingCount: 372, totalCount: 400)
                    HomeImportProgressBar(remainingCount: 128, totalCount: 400)
                    HomeImportProgressBar(remainingCount: 1, totalCount: 400)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private func header(pendingImports: Int) -> some View {
        HStack {
            AscendWordmark(size: 16, letterColor: .white)

            Spacer()

            NotificationBellView(pendingImports: pendingImports) {}
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func panel<Content: View>(
        caption: String,
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption.uppercased())
                .font(.montserratSemiBold(size: 11))
                .foregroundStyle(Color.ascendAccent.opacity(0.9))

            Text(note)
                .font(.montserratRegular(size: 11))
                .foregroundStyle(.white.opacity(0.6))

            content()
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
