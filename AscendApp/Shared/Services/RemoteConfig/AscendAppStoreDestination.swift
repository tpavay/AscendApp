import Foundation

enum AscendAppStoreDestination {
    static let productID = "6757202987"

    static var productURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(productID)")
    }
}
