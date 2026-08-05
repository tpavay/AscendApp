import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Renders every state of the sync row the climber can actually reach, so the surface can be
/// reviewed visually rather than only through assertions. Writes PNGs to `ASCEND_EVIDENCE_DIR`.
///
/// One caveat worth knowing before reading the output: `ImageRenderer` cannot snapshot
/// `ProgressView`, so the retrying state's spinner appears as a placeholder glyph in the PNG. The
/// app draws a real spinner there, and Reduce Motion drops it.
@MainActor
struct WorkoutSyncSurfaceEvidenceTests {
    @Test
    func capturesTheTryAgainLoopStateByState() throws {
        let states: [(String, String, WorkoutSyncPresentation)] = [
            ("01-syncing-quiet", "Quiet automatic series - no control, nothing to do", .syncing),
            ("02-couldnt-sync", "State 1: stopped, TRY AGAIN live", .couldNotSync),
            ("03-syncing-after-tap", "State 2: tapped - control disabled, row unchanged (ImageRenderer cannot snapshot ProgressView; the glyph is its placeholder, the app draws a spinner)", .couldNotSyncRetrying),
            ("04-failed-again", "State 3: refused again - identical to state 1, by design", .couldNotSync),
            ("05-offline", "Offline: the fact is unchanged, the action is dead", .couldNotSyncOffline),
            ("06-synced", "State 4: landed - the only state that disappears", .synced)
        ]

        for (name, caption, presentation) in states {
            try Self.render(
                name: name,
                caption: caption,
                content: WorkoutSyncStatusRow(
                    presentation: presentation,
                    effectiveColorScheme: .dark,
                    onRetry: {}
                )
            )
        }
    }

    /// The row is mounted unconditionally, so `hidden` has to cost nothing.
    ///
    /// Its host owns the state that drives it precisely so the screen's expensive derivations do
    /// not re-run when it changes; that only works if the caller never has to ask whether to place
    /// it. A hidden row that still took a slot would add the stack's spacing to a screen showing
    /// no row at all.
    @Test
    func aHiddenRowTakesNoSpaceSoItCanBeMountedUnconditionally() throws {
        #expect(WorkoutSyncPresentation.hidden.showsRow == false)

        for presentation in [
            WorkoutSyncPresentation.syncing,
            .couldNotSync,
            .couldNotSyncOffline,
            .couldNotSyncRetrying,
            .synced
        ] {
            #expect(presentation.showsRow, "\(presentation) has something to say.")
        }

        let hiddenHeight = Self.renderedHeight(of: WorkoutSyncStatusRow(
            presentation: .hidden,
            effectiveColorScheme: .dark,
            onRetry: {}
        ))
        let visibleHeight = Self.renderedHeight(of: WorkoutSyncStatusRow(
            presentation: .couldNotSync,
            effectiveColorScheme: .dark,
            onRetry: {}
        ))

        #expect(visibleHeight > 0, "A row with something to say must draw.")
        #expect(hiddenHeight == 0, "A hidden row must draw nothing at all.")
    }

    /// Zero for content that draws nothing - `ImageRenderer` produces no image for an empty view,
    /// which is the same answer as a zero-height one for the question being asked here. The
    /// visible case proves the renderer works, so a nil cannot pass vacuously.
    @MainActor
    private static func renderedHeight(of content: some View) -> CGFloat {
        ImageRenderer(content: content.frame(width: 402)).uiImage?.size.height ?? 0
    }

    private static func render(
        name: String,
        caption: String,
        content: some View
    ) throws {
        let framed = VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            content
        }
        .padding(20)
        .frame(width: 402)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3

        guard let image = renderer.uiImage, let data = image.pngData() else {
            Issue.record("ImageRenderer produced no output for \(name)")
            return
        }

        let candidates = [
            ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"],
            NSTemporaryDirectory().appending("ascend-sync-surface-evidence")
        ].compactMap { $0 }

        for directory in candidates {
            let url = URL(filePath: directory).appending(path: "\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: URL(filePath: directory),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
                print("ASCEND_EVIDENCE_PNG \(url.path)")
                return
            } catch {
                continue
            }
        }
        Issue.record("No writable evidence directory for \(name)")
    }
}
