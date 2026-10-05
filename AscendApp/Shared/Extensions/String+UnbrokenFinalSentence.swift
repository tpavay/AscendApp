import Foundation

extension String {
    /// The same text with its final sentence held together by non-breaking spaces.
    ///
    /// For state-then-command copy drawn in a narrow column: when the line has to wrap it breaks
    /// between the two sentences, and never strands half of a three-word command ("Pull" / "to
    /// retry.") on a line of its own. A single sentence is returned unchanged, because holding a
    /// whole line together would stop it wrapping at all.
    var keepingFinalSentenceUnbroken: String {
        guard let boundary = range(of: ". ", options: .backwards) else { return self }

        let finalSentence = String(self[boundary.upperBound...]).replacing(" ", with: "\u{00A0}")
        return String(self[..<boundary.upperBound]) + finalSentence
    }
}
