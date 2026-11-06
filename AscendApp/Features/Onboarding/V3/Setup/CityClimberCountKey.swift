import Foundation

/// The document id of `public_city_climber_counts` for a city. `functions/src/publicCityClimberCounts.ts`
/// writes the counts under the same key, and `SharedTestVectors/city-count-key-vector.json` holds
/// the two implementations to the same answers.
enum CityClimberCountKey {
    static func key(city: String, region: String?, countryCode: String) -> String? {
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cityPart = normalized(city)
        guard country.count == 2,
              country.allSatisfy({ $0.isASCII && $0.isLetter }),
              !cityPart.isEmpty else { return nil }

        let regionPart = region.map(normalized) ?? ""
        return "\(country)__\(regionPart.isEmpty ? "none" : regionPart)__\(cityPart)"
    }

    static func key(for selection: PostAuthLocationSelection) -> String? {
        key(city: selection.city, region: selection.region, countryCode: selection.countryCode)
    }

    /// Trimmed, accents folded, lower case, every run of other characters one hyphen.
    private static func normalized(_ value: String) -> String {
        let unaccented = String(
            String.UnicodeScalarView(
                value.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
                    !$0.properties.generalCategory.isMark
                }
            )
        )
        let hyphenated = unaccented.lowercased().replacing(/[^a-z0-9]+/, with: "-")
        return hyphenated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension Unicode.GeneralCategory {
    var isMark: Bool {
        switch self {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }
}
