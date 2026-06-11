import Foundation

enum ProfileIdentityFormatter {
    static func demographicsLine(
        for identity: ProfileUserIdentity,
        measurementSystem: MeasurementSystem
    ) -> String? {
        var parts: [String] = []

        if let age = identity.age {
            parts.append("\(age)")
        }

        if let gender = identity.gender {
            parts.append(gender.compactProfileDisplay)
        }

        if let weightKg = identity.weightKg, weightKg > 0 {
            let weightValue: Double
            switch measurementSystem {
            case .imperial:
                weightValue = MeasurementSystem.metric.convertWeight(weightKg, to: .imperial)
            case .metric:
                weightValue = weightKg
            }
            parts.append(measurementSystem.formatWeight(weightValue))
        }

        if let location = locationText(
            city: identity.locationCity,
            countryCode: identity.locationCountryCode,
            regionCode: identity.locationRegionCode
        ) {
            parts.append(location)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func joinedDateText(for date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }

        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Joined today"
        }

        return "Member since \(monthDayYearFormatter.string(from: date))"
    }

    static func pullStatText(for snapshot: ProfileSnapshot, mode: ProfileViewMode) -> String {
        let climbs = snapshot.stats.totalClimbsCompleted
        let firstAscents = snapshot.stats.totalFirstAscents
        let streak = snapshot.stats.currentStreakWeeks

        if mode == .own, climbs == 0 {
            return "New climber"
        }

        return [
            "\(climbs) \(climbs == 1 ? "climb" : "climbs")",
            "\(firstAscents) \(firstAscents == 1 ? "First Ascent" : "First Ascents")",
            "\(streak) \(streak == 1 ? "week" : "weeks") streak"
        ].joined(separator: " · ")
    }

    private static func locationText(city: String?, countryCode: String?, regionCode: String?) -> String? {
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty {
            if let regionCode = regionCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !regionCode.isEmpty {
                return "\(city), \(regionCode)"
            }

            if let countryCode,
               let countryName = Locale.current.localizedString(forRegionCode: countryCode.uppercased()) {
                return "\(city), \(countryName)"
            }

            return city
        }

        guard let countryCode, !countryCode.isEmpty else { return nil }

        if countryCode.uppercased() == "US", let regionCode, !regionCode.isEmpty {
            return regionCode.uppercased()
        }

        if let countryName = Locale.current.localizedString(forRegionCode: countryCode.uppercased()) {
            if let regionCode, !regionCode.isEmpty {
                return "\(regionCode.uppercased()), \(countryName)"
            }
            return countryName
        }

        return countryCode.uppercased()
    }

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

private extension ProfileGender {
    var compactProfileDisplay: String {
        switch self {
        case .woman:
            "F"
        case .man:
            "M"
        case .nonBinary:
            "NB"
        case .preferNotToSay:
            "Private"
        }
    }
}
