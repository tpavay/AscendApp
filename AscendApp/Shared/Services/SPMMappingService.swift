import Foundation

enum SPMMappingService {
    static let levelToSPM = [
        24, 31, 38, 45, 52,
        59, 66, 73, 80, 86,
        93, 100, 107, 114, 121,
        128, 134, 141, 148, 155,
        162, 169, 176, 183, 190
    ]

    static func clampedLevel(_ level: Int) -> Int {
        min(max(level, 1), levelToSPM.count)
    }

    static func spm(forLevel level: Int) -> Int {
        levelToSPM[clampedLevel(level) - 1]
    }

    static func level(forSPM spm: Double) -> Int {
        let nearestIndex = levelToSPM.enumerated().min { lhs, rhs in
            abs(Double(lhs.element) - spm) < abs(Double(rhs.element) - spm)
        }?.offset ?? 0
        return nearestIndex + 1
    }
}
