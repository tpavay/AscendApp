import Foundation

enum ProfileIdentityFormatter {
    static func locationLine(
        for demographics: ProfileDemographicsSnapshot
    ) -> String? {
        locationText(
            city: demographics.locationCity,
            countryCode: demographics.locationCountryCode,
            regionCode: demographics.locationRegionCode
        )
    }

    static func joinedDateText(for date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }

        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Joined today"
        }

        return "Member since \(monthDayYearFormatter.string(from: date))"
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
