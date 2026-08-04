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
    /// itself, so this asserts the vocabulary: neither builder file may contain a raw animation
    /// identifier at all - `.spring` and `.spring(...)` alike, and a `?? .default` fallback
    /// beside a helper call.
    ///
    /// What this proves and nothing more: those two files construct no animation of their own,
    /// so the Reduce Motion answer cannot be bypassed by writing one there. It does not observe
    /// a rendered frame, and it would not catch an animation built somewhere else and handed in.
    @Test
    func neitherBuilderFileNamesAnAnimationOfItsOwn() throws {
        var offences: [String] = []

        for source in Self.builderSources {
            let text = try String(contentsOf: source.url, encoding: .utf8)

            for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                let line = rawLine.components(separatedBy: "//")[0]

                for token in try Self.rawAnimationTokens(in: line) {
                    offences.append("\(source.name):\(offset + 1) names \(token) - \(line.trimmingCharacters(in: .whitespaces))")
                }
            }

            #expect(
                text.contains("RoutineTimelineMotion."),
                "\(source.name) no longer reads RoutineTimelineMotion - the guard may be reading the wrong file"
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

    private static var builderSources: [(name: String, url: URL)] {
        let views = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "AscendApp/Features/Routines/Views")

        return [
            ("RoutineEditorView.swift", views.appending(path: "RoutineEditorView.swift")),
            (
                "RoutineTimelineEditor.swift",
                views.appending(path: "Components/RoutineTimelineEditor.swift")
            )
        ]
    }
}
