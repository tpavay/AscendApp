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
    func reduceMotionLeavesNothingAnimatingTheTimeline() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.resize(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.reorder(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: true) == nil)
    }

    /// The springs are the approved design, so reduced mode is the only thing that turns them
    /// off - this is what stops a "fix" from flattening the timeline for everyone.
    @Test
    func everyMotionStillSpringsWhenReduceMotionIsOff() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: false) == .spring(response: 0.3, dampingFraction: 0.62))
        #expect(RoutineTimelineMotion.resize(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 0.85))
        #expect(RoutineTimelineMotion.reorder(reduceMotion: false) == .spring(response: 0.36, dampingFraction: 0.78))
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: false) == .easeInOut(duration: 0.2))
    }

    // MARK: - Source guard

    /// The contract above only binds the builder while the builder names no animation of its
    /// own: one literal written into a `withAnimation` or an `.animation(_:value:)` would run
    /// whatever Reduce Motion says. So every animation site in both builder files is read out
    /// of the source and its animation argument has to be a `RoutineTimelineMotion` call, or an
    /// `Animation?` property that is itself one. Anything else fails, including a spelling this
    /// test has never seen - a site is allowed by what it *is*, not by what it is not.
    ///
    /// This is a source-level guard, and only that. It keeps every animation routed through the
    /// one helper whose Reduce Motion answer is asserted above; it does not observe a rendered
    /// frame and is not evidence of what SwiftUI actually draws.
    @Test
    func everyAnimationOnTheBuilderRoutesThroughRoutineTimelineMotion() throws {
        var offenders: [String] = []

        for source in Self.builderSources {
            let text = try String(contentsOf: source.url, encoding: .utf8)
            let helperBackedProperties = Self.helperBackedAnimationProperties(in: text)
            let sites = Self.animationSites(in: text, fileName: source.name)

            #expect(!sites.isEmpty, "Found no animation site in \(source.name) - the guard has stopped reading it")

            for site in sites where !Self.isRouted(
                site,
                helperBackedProperties: helperBackedProperties
            ) {
                offenders.append("\(site.file):\(site.line) - \(site.expression)")
            }

            for exemption in Self.exemptions where exemption.file == source.name {
                let found = sites.filter { $0.expression == exemption.expression }.count
                #expect(
                    found == exemption.occurrences,
                    """
                    \(source.name) has \(found) sites using \(exemption.expression), expected \
                    \(exemption.occurrences). The exemption covers only: \(exemption.reason)
                    """
                )
            }
        }

        #expect(
            offenders.isEmpty,
            """
            These animations bypass RoutineTimelineMotion, so Reduce Motion cannot turn them off:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    private static func isRouted(_ site: AnimationSite, helperBackedProperties: Set<String>) -> Bool {
        if site.expression.hasPrefix("RoutineTimelineMotion.") { return true }
        if helperBackedProperties.contains(site.expression) { return true }
        return exemptions.contains { $0.file == site.file && $0.expression == site.expression }
    }

    // MARK: - Reading the source

    private struct AnimationSite {
        let file: String
        let line: Int
        let expression: String
    }

    /// A site the guard deliberately lets through, recorded rather than skipped. The count is
    /// pinned so a second animation cannot hide behind the first one's spelling.
    private struct Exemption {
        let file: String
        let expression: String
        let occurrences: Int
        let reason: String
    }

    private static let exemptions = [
        Exemption(
            file: "RoutineEditorView.swift",
            expression: ".easeInOut(duration: 0.2)",
            occurrences: 1,
            reason: "the Advanced Settings disclosure, which predates the timeline and moves no block"
        )
    ]

    private static var builderSources: [(name: String, url: URL)] {
        let features = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "AscendApp/Features/Routines/Views")

        return [
            ("RoutineEditorView.swift", features.appending(path: "RoutineEditorView.swift")),
            (
                "RoutineTimelineEditor.swift",
                features.appending(path: "Components/RoutineTimelineEditor.swift")
            )
        ]
    }

    private static func animationSites(in source: String, fileName: String) -> [AnimationSite] {
        var sites: [AnimationSite] = []

        for (offset, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.components(separatedBy: "//")[0]

            for marker in ["withAnimation(", ".animation("] {
                var searchStart = line.startIndex

                while let marked = line.range(of: marker, range: searchStart..<line.endIndex) {
                    sites.append(
                        AnimationSite(
                            file: fileName,
                            line: offset + 1,
                            expression: firstArgument(from: marked.upperBound, in: line)
                        )
                    )
                    searchStart = marked.upperBound
                }
            }
        }

        return sites
    }

    private static func firstArgument(from index: String.Index, in line: String) -> String {
        var depth = 0
        var argument = ""

        for character in line[index...] {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 { break }
                depth -= 1
            } else if character == ",", depth == 0 {
                break
            }
            argument.append(character)
        }

        return argument.trimmingCharacters(in: .whitespaces)
    }

    /// `Animation?` properties whose own body reads the helper. A property that names an
    /// animation itself is deliberately left out, so a site using it is reported.
    private static func helperBackedAnimationProperties(in source: String) -> Set<String> {
        let lines = source.components(separatedBy: .newlines)
        var properties: Set<String> = []

        for (offset, line) in lines.enumerated() {
            guard line.contains(": Animation?"), let name = declaredName(in: line) else { continue }

            let body = lines[offset..<min(offset + 8, lines.count)].joined(separator: "\n")
            if body.contains("RoutineTimelineMotion.") {
                properties.insert(name)
            }
        }

        return properties
    }

    private static func declaredName(in line: String) -> String? {
        guard let keyword = line.range(of: "var ") else { return nil }
        let remainder = line[keyword.upperBound...]
        guard let colon = remainder.firstIndex(of: ":") else { return nil }
        return String(remainder[..<colon]).trimmingCharacters(in: .whitespaces)
    }
}
