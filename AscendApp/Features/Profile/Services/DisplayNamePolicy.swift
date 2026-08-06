import Foundation

enum DisplayNamePolicy {
    static let maximumLength = 80

    private static let blockedTerms = [
        "asshole",
        "bastard",
        "bitch",
        "blowjob",
        "chink",
        "cock",
        "cunt",
        "dick",
        "douchebag",
        "dyke",
        "fag",
        "faggot",
        "fuck",
        "fucker",
        "fucking",
        "heilhitler",
        "hitler",
        "jackass",
        "kike",
        "killyourself",
        "motherfucker",
        "nazi",
        "nigga",
        "nigger",
        "pedo",
        "pedophile",
        "piss",
        "pussy",
        "rape",
        "rapist",
        "retard",
        "retarded",
        "shit",
        "slut",
        "spic",
        "wetback",
        "whore",
        "white power"
    ].map { $0.replacing(" ", with: "") }

    private static let embeddedBlockedTerms = [
        "faggot",
        "fuck",
        "fucker",
        "nigger",
        "pedophile"
    ]

    static func validated(_ candidate: String) throws -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else {
            throw DisplayNamePolicyError.invalidLength
        }
        guard containsUnsupportedCompatibilityGlyph(trimmed) == false else {
            throw DisplayNamePolicyError.objectionable
        }

        let folded = foldedForScreening(trimmed)
        guard containsLongASCIILetterRun(folded) == false else {
            throw DisplayNamePolicyError.objectionable
        }

        let normalized = digitSubstituted(folded)
        let lettersOnly = normalized.filter { $0.isASCII && $0.isLetter }
        guard lettersOnly != "anonymousclimber" else {
            throw DisplayNamePolicyError.objectionable
        }
        guard !blockedTerms.contains(lettersOnly) else {
            throw DisplayNamePolicyError.objectionable
        }
        guard containsObscuredBlockedTerm(in: normalized) == false else {
            throw DisplayNamePolicyError.objectionable
        }
        guard !embeddedBlockedTerms.contains(where: lettersOnly.contains) else {
            throw DisplayNamePolicyError.objectionable
        }

        return trimmed
    }

    static func isAllowed(_ candidate: String) -> Bool {
        (try? validated(candidate)) != nil
    }

    /// The public board name a climber's two required name halves compose into.
    ///
    /// Both halves are required: composing from one would republish a partial
    /// name over the one a legacy climber already ranks under.
    static func composedBoardName(firstName: String, lastName: String) throws -> String {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !last.isEmpty else {
            throw DisplayNamePolicyError.incompleteName
        }
        return try validated("\(first) \(last)")
    }

    static func composesAllowedBoardName(firstName: String, lastName: String) -> Bool {
        (try? composedBoardName(firstName: firstName, lastName: lastName)) != nil
    }

    /// Case, diacritic, and confusable-letter folding only.
    ///
    /// Digits stay digits here so the repeated-character check cannot invent a
    /// letter run out of an ordinary numeric name like `Climber2000`.
    private static func foldedForScreening(_ value: String) -> String {
        let folded = value
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let substitutions: [Character: Character] = [
            "а": "a",
            "ɑ": "a",
            "α": "a",
            "β": "b",
            "е": "e",
            "ё": "e",
            "ε": "e",
            "і": "i",
            "ӏ": "i",
            "ι": "i",
            "κ": "k",
            "о": "o",
            "ο": "o",
            "р": "p",
            "ρ": "p",
            "с": "c",
            "τ": "t",
            "υ": "u",
            "х": "x",
            "χ": "x",
            "у": "y",
            "ս": "u"
        ]

        return String(folded.map { substitutions[$0] ?? $0 })
    }

    /// Leetspeak folding, applied only to the blocked-term checks.
    private static func digitSubstituted(_ folded: String) -> String {
        let substitutions: [Character: Character] = [
            "0": "o",
            "1": "i",
            "3": "e",
            "4": "a",
            "5": "s",
            "7": "t",
            "@": "a",
            "$": "s",
            "!": "i"
        ]

        return String(folded.map { substitutions[$0] ?? $0 })
    }

    private static func containsUnsupportedCompatibilityGlyph(
        _ value: String
    ) -> Bool {
        value.unicodeScalars.contains { scalar in
            let codePoint = scalar.value
            // U+02BB okina and U+02BC modifier apostrophe carry meaning in
            // Hawaiian and many other orthographies, so they stay spellable.
            if codePoint == 0x02BB || codePoint == 0x02BC {
                return false
            }
            return (0x02B0...0x02FF).contains(codePoint) ||
                (0x1D00...0x1D7F).contains(codePoint) ||
                (0x2070...0x209F).contains(codePoint) ||
                (0x2100...0x218F).contains(codePoint) ||
                (0x2460...0x24FF).contains(codePoint) ||
                (0x3200...0x33FF).contains(codePoint) ||
                (0xFB00...0xFB06).contains(codePoint) ||
                (0xFE10...0xFE6B).contains(codePoint) ||
                (0xFF00...0xFFEF).contains(codePoint) ||
                (0x1D400...0x1D7FF).contains(codePoint) ||
                (0x1F100...0x1F2FF).contains(codePoint)
        }
    }

    /// Screening runs on every keystroke of the onboarding name fields, so the
    /// patterns are compiled once per process rather than once per check.
    private static let longASCIILetterRunExpression = try? NSRegularExpression(
        pattern: #"([a-z])\1{2,}"#
    )

    private static let obscuredBlockedTermExpressions: [NSRegularExpression] =
        blockedTerms.compactMap { term in
            let letters = term.map {
                NSRegularExpression.escapedPattern(for: String($0))
            }
            let pattern = "(^|[^a-z])" +
                letters.joined(separator: "[^a-z]*") +
                "([^a-z]|$)"
            return try? NSRegularExpression(pattern: pattern)
        }

    private static func containsLongASCIILetterRun(_ value: String) -> Bool {
        guard let longASCIILetterRunExpression else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return longASCIILetterRunExpression.firstMatch(in: value, range: range) != nil
    }

    private static func containsObscuredBlockedTerm(in normalized: String) -> Bool {
        let range = NSRange(normalized.startIndex..., in: normalized)
        return obscuredBlockedTermExpressions.contains { expression in
            expression.firstMatch(in: normalized, range: range) != nil
        }
    }
}
