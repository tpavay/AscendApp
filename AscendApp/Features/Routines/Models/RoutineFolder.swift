import Foundation
import SwiftData

@Model
final class RoutineFolder {
    var id: UUID
    var name: String
    var colorHex: String?
    var order: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.createdAt = Date()
    }
}
