import Foundation
import SwiftUI
import Testing
@testable import AscendApp

struct RoutineTimelineMotionTests {
    /// Reduce Motion is a must-have on this screen. Every animation here moves geometry - block
    /// width, block height, the reorder lift, the neighbours parting - and an easing curve is
    /// still motion, so the reduced answer is no animation at all and the change lands in one
    /// frame.
    @Test
    func reduceMotionLeavesNothingAnimatingTheBuilder() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.resize(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.reorder(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.sectionReveal(reduceMotion: true) == nil)
    }

    /// The springs are the approved design, so reduced mode is the only thing that turns them
    /// off - this is what stops a "fix" from flattening the timeline for everyone.
    @Test
    func everyMotionStillSpringsWhenReduceMotionIsOff() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: false) == .spring(response: 0.3, dampingFraction: 0.62))
        #expect(RoutineTimelineMotion.resize(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 0.85))
        #expect(RoutineTimelineMotion.reorder(reduceMotion: false) == .spring(response: 0.36, dampingFraction: 0.78))
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: false) == .easeInOut(duration: 0.2))
        #expect(RoutineTimelineMotion.sectionReveal(reduceMotion: false) == .easeInOut(duration: 0.2))
    }

    // MARK: - Source guard

    /// The contract above binds the builder only while the builder never names an animation
    /// itself, so this asserts the vocabulary: no builder file may contain a raw animation
    /// identifier at all - `.spring` and `.spring(...)` alike, and a `?? .default` fallback
    /// beside a helper call.
    ///
    /// It sweeps every view the builder is made of rather than a hand-written list, because a
    /// list goes stale the moment a component is added - which is exactly when a raw animation
    /// gets written. The two owners are named separately below, so the sweep cannot silently
    /// stop reading the files that actually decide the motion.
    ///
    /// What this proves and nothing more: those files construct no animation of their own, so
    /// the Reduce Motion answer cannot be bypassed by writing one there. It does not observe a
    /// rendered frame, and it would not catch an animation built somewhere else and handed in.
    @Test
    func noBuilderFileNamesAnAnimationOfItsOwn() throws {
        var offences: [String] = []
        let sources = try Self.builderSources

        #expect(sources.count >= 4, "The builder's views were not found - the guard is reading nothing")

        for source in sources {
            let text = try String(contentsOf: source.url, encoding: .utf8)

            for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                let line = rawLine.components(separatedBy: "//")[0]

                for token in try Self.rawAnimationTokens(in: line) {
                    offences.append("\(source.name):\(offset + 1) names \(token) - \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        for name in Self.motionOwners {
            let owner = try #require(sources.first { $0.name == name }, "\(name) is no longer in the builder's views")
            let text = try String(contentsOf: owner.url, encoding: .utf8)

            #expect(
                text.contains("RoutineTimelineMotion."),
                "\(name) no longer reads RoutineTimelineMotion - the guard may be reading the wrong file"
            )
        }

        #expect(
            offences.isEmpty,
            """
            The routine builder must take every animation from RoutineTimelineMotion, which is \
            the only place Reduce Motion is honoured:
            \(offences.joined(separator: "\n"))
            """
        )
    }

    /// The guard above is only worth its green tick if it actually rejects the things it claims
    /// to, so this tests the matcher itself against the bypasses that have slipped past earlier
    /// versions of it - a parenless static value, a coalesced fallback - and against the shapes
    /// it must not cry wolf over.
    @Test
    func theGuardRejectsEveryRawAnimationAndNothingElse() throws {
        let mustReject = [
            ".animation(.spring, value: x)",
            "withAnimation(.easeInOut)",
            "withAnimation(RoutineTimelineMotion.resize(reduceMotion: r) ?? .default)",
            ".animation(.interpolatingSpring, value: x)",
            ".animation(.interactiveSpring, value: x)",
            "withAnimation(.easeInOut(duration: 0.2)) {",
            ".animation(.linear, value: x)",
            ".animation(.timingCurve(0.2, 0, 0.8, 1), value: x)",
            "withAnimation(.snappy) {",
            "withAnimation(.smooth) {",
            "withAnimation(.bouncy) {",
            "let curve = Animation(MyCustomTiming())",
            "let held = .spring",
            "withAnimation(.easeOut) {",
            "withAnimation(.easeIn) {"
        ]

        for line in mustReject {
            #expect(
                try !Self.rawAnimationTokens(in: line).isEmpty,
                "The guard would let this through: \(line)"
            )
        }

        let mustAccept = [
            ".animation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion), value: intervals)",
            "withAnimation(RoutineTimelineMotion.selection(reduceMotion: reduceMotion)) {",
            "$viewModel.defaultWeightConfiguration,",
            ".springLoaded(true)",
            "Button { } label: { }",
            "private var resizeAnimation: Animation? {"
        ]

        for line in mustAccept {
            #expect(
                try Self.rawAnimationTokens(in: line).isEmpty,
                "The guard cries wolf over: \(line)"
            )
        }

        // Longest-first, so `.easeInOut` is never reported as `.easeIn`.
        #expect(try Self.rawAnimationTokens(in: "withAnimation(.easeInOut)") == [".easeInOut"])
        #expect(try Self.rawAnimationTokens(in: ".animation(.interactiveSpring)") == [".interactiveSpring"])
    }

    /// Every way SwiftUI spells "make me an animation", matched as a whole identifier so both
    /// `.spring` and `.spring(` are caught while `.springLoaded` is not. `Animation(` needs the
    /// leading word boundary because it also spells the tail of `withAnimation(`.
    private static let rawAnimationPattern = """
        \\.(?:interactiveSpring|interpolatingSpring|easeInOut|easeIn|easeOut|timingCurve\
        |spring|linear|default|snappy|smooth|bouncy)(?![A-Za-z0-9_])|\\bAnimation\\(
        """

    private static func rawAnimationTokens(in line: String) throws -> [String] {
        let regex = try Regex(rawAnimationPattern)
        return line.matches(of: regex).map { String(line[$0.range]) }
    }

    /// The two files that decide the builder's motion. Everything else is swept for raw
    /// animations; these two must also still be reading the one place Reduce Motion lives.
    private static let motionOwners = ["RoutineEditorView.swift", "RoutineTimelineEditor.swift"]

    /// The routine views that are *not* the builder: the reading and browsing surfaces, the
    /// live session, and `RoutineTimelineMotion` itself - the one file whose whole job is to
    /// name animations. Those may legitimately spell an animation out.
    ///
    /// Excluding by name rather than including by name is the whole point: a builder component
    /// added tomorrow is swept without anyone remembering to widen a list, and a naming
    /// convention nobody predicted cannot make it disappear from the guard in silence.
    private static let nonBuilderSources: Set<String> = [
        "ActiveRoutineView.swift",
        "BookmarkButton.swift",
        "DifficultyIndicator.swift",
        "LiveWorkoutControlButton.swift",
        "PracticeView.swift",
        "RoutineCard.swift",
        "RoutineCardSurface.swift",
        "RoutineDetailView.swift",
        "RoutineGhostCard.swift",
        "RoutineHeroVisualization.swift",
        "RoutineHorizontalRail.swift",
        "RoutineIntensityBarChart.swift",
        "RoutineIntervalDetailRow.swift",
        "RoutineListCard.swift",
        "RoutineThumbnailCard.swift",
        "RoutineTimelineMotion.swift",
        "RoutinesView.swift",
        "SegmentedProgressBar.swift"
    ]

    /// Every view under the routines feature except those, discovered rather than listed.
    private static var builderSources: [(name: String, url: URL)] {
        get throws {
            try routineViewSources.filter { !nonBuilderSources.contains($0.name) }
        }
    }

    private static var routineViewSources: [(name: String, url: URL)] {
        get throws {
            let views = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "AscendApp/Features/Routines/Views")

            return try FileManager.default
                .subpathsOfDirectory(atPath: views.path(percentEncoded: false))
                .filter { $0.hasSuffix(".swift") }
                .sorted()
                .map { (name: URL(filePath: $0).lastPathComponent, url: views.appending(path: $0)) }
        }
    }

    /// An exclusion list rots the other way round: a file renamed or deleted leaves a name
    /// behind that would quietly excuse a future file that happens to take it.
    @Test
    func theExclusionListNamesNothingThatHasGoneAway() throws {
        let present = Set(try Self.routineViewSources.map(\.name))
        let stale = Self.nonBuilderSources.subtracting(present).sorted()

        #expect(
            stale.isEmpty,
            "These are excluded from the Reduce Motion sweep but no longer exist: \(stale.joined(separator: ", "))"
        )
    }
}
