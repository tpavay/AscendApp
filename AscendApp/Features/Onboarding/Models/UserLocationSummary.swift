import Foundation

struct UserLocationSummary: Codable, Equatable {
    var country: String
    var region: String
    var city: String

    static let empty = UserLocationSummary(country: "", region: "", city: "")

    var isEmpty: Bool {
        country.isEmpty && region.isEmpty && city.isEmpty
    }
}
