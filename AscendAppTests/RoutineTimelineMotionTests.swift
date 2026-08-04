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
    /// token at all. Not `.spring(...)`, not a `?? .default` fallback beside a helper call, not
    /// one hidden behind an intermediate property - the words simply may not appear, whatever
    /// the surrounding expression looks like.
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

                for token in Self.rawAnimationTokens(in: line) {
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

    /// Every way SwiftUI spells "make me an animation". A raw one of these in a builder file is
    /// an animation that Reduce Motion cannot switch off.
    private static let animationVocabulary = [
        ".spring(", ".interactiveSpring(", ".easeInOut(", ".easeIn(", ".easeOut(",
        ".linear(", ".timingCurve(", ".default", ".snappy", ".smooth", ".bouncy", "Animation("
    ]

    private static func rawAnimationTokens(in line: String) -> [String] {
        animationVocabulary.filter { token in
            var searchStart = line.startIndex

            while let found = line.range(of: token, range: searchStart..<line.endIndex) {
                // `Animation(` also spells the tail of `withAnimation(`, and `.default` the head
                // of `.defaultWeightConfiguration`. Neither makes an animation.
                let borrowsAName = !token.hasPrefix(".")
                    && isIdentifierCharacter(line[safe: line.index(before: found.lowerBound)])
                let isLongerName = !token.hasSuffix("(")
                    && isIdentifierCharacter(line[safe: found.upperBound])

                if !borrowsAName, !isLongerName { return true }
                searchStart = found.upperBound
            }

            return false
        }
    }

    private static func isIdentifierCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
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

private extension String {
    subscript(safe index: String.Index) -> Character? {
        guard index >= startIndex, index < endIndex else { return nil }
        return self[index]
    }
}
