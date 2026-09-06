import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Photographs every state of the sync row the climber can actually reach, so the surface can be
/// reviewed visually rather than only through assertions. The PNGs are written only when
/// `ASCEND_EVIDENCE_DIR` is set; every run still proves each state lays out to a row at all.
///
/// One caveat worth knowing before reading the output: the photograph is an offscreen render,
/// which cannot snapshot `ProgressView`, so the retrying state's spinner appears as a placeholder
/// glyph in the PNG. The app draws a real spinner there, and Reduce Motion drops it.
@MainActor
struct WorkoutSyncSurfaceEvidenceTests {
    @Test
    func capturesTheTryAgainLoopStateByState() throws {
        let states: [(String, String, WorkoutSyncPresentation)] = [
            ("01-syncing-quiet", "Quiet automatic series - no control, nothing to do", .syncing),
            ("02-couldnt-sync", "State 1: stopped, TRY AGAIN live", .couldNotSync),
            ("03-syncing-after-tap", "State 2: tapped - control disabled, row unchanged (an offscreen render cannot snapshot ProgressView; the glyph is its placeholder, the app draws a spinner)", .couldNotSyncRetrying),
            ("04-failed-again", "State 3: refused again - identical to state 1, by design", .couldNotSync),
            ("05-offline", "Offline: the fact is unchanged, the action is dead", .couldNotSyncOffline),
            ("06-synced", "State 4: landed - the only state that disappears", .synced)
        ]

        for (name, caption, presentation) in states {
            let row = WorkoutSyncStatusRow(
                presentation: presentation,
                effectiveColorScheme: .dark,
                onRetry: {}
            )
            #expect(Self.layoutHeight(of: row) > 0, "\(name) drew nothing")

            try Self.photograph(name: name, caption: caption, content: row)
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

        let hiddenHeight = Self.layoutHeight(of: WorkoutSyncStatusRow(
            presentation: .hidden,
            effectiveColorScheme: .dark,
            onRetry: {}
        ))
        let visibleHeight = Self.layoutHeight(of: WorkoutSyncStatusRow(
            presentation: .couldNotSync,
            effectiveColorScheme: .dark,
            onRetry: {}
        ))

        #expect(visibleHeight > 0, "A row with something to say must draw.")
        #expect(hiddenHeight == 0, "A hidden row must draw nothing at all.")
    }

    /// The height the row lays out to at phone width, asked of a hosting controller rather than
    /// read off a bitmap. A body that draws nothing measures zero, which is the same answer as a
    /// zero-height one for the question being asked here. The visible case proves the measurement
    /// works, so a zero cannot pass vacuously.
    private static func layoutHeight(of content: some View) -> CGFloat {
        UIHostingController(rootView: content.frame(width: 402))
            .sizeThatFits(in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude))
            .height
    }

    /// The captioned proof of one state, written to `ASCEND_EVIDENCE_DIR` and nowhere else.
    private static func photograph(
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

        try RenderedScreen.photograph(framed, named: name)
    }
}
