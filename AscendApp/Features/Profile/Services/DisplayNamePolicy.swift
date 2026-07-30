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

        let normalized = normalizedForScreening(trimmed)
        guard containsLongASCIILetterRun(normalized) == false else {
            throw DisplayNamePolicyError.objectionable
        }
        let lettersOnly = normalized.filter { $0.isLetter }
        guard lettersOnly != "anonymousclimber" else {
            throw DisplayNamePolicyError.objectionable
        }
        guard !blockedTerms.contains(lettersOnly) else {
            throw DisplayNamePolicyError.objectionable
        }
        guard !blockedTerms.contains(where: {
            containsObscuredTerm($0, in: normalized)
        }) else {
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

    private static func normalizedForScreening(_ value: String) -> String {
        let folded = value
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let substitutions: [Character: Character] = [
            "0": "o",
            "1": "i",
            "3": "e",
            "4": "a",
            "5": "s",
            "7": "t",
            "@": "a",
            "$": "s",
            "!": "i",
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

    private static func containsLongASCIILetterRun(_ value: String) -> Bool {
        value.range(
            of: #"([a-z])\1{2,}"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsObscuredTerm(
        _ term: String,
        in normalized: String
    ) -> Bool {
        let letters = term.map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        let pattern = "(^|[^a-z])" +
            letters.joined(separator: "[^a-z]*") +
            "([^a-z]|$)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return expression.firstMatch(in: normalized, range: range) != nil
    }
}
