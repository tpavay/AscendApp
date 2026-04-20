import Foundation

struct FirestoreWorkoutWeightEntry: Codable, Equatable, Sendable {
    let id: String
    let equipmentType: String
    let weightValue: Double
    let isEnabled: Bool

    init(
        id: String,
        equipmentType: String,
        weightValue: Double,
        isEnabled: Bool
    ) {
        self.id = id
        self.equipmentType = equipmentType
        self.weightValue = weightValue
        self.isEnabled = isEnabled
    }
}
