import SwiftUI

extension HeartRateZone {
    /// Zone colors shown during live sessions: blue → green → amber as
    /// effort rises. Green is the brand accent so the "working" zone reads
    /// as the app's home state.
    var color: Color {
        switch self {
        case .recovery:
            return Color(red: 0.29, green: 0.62, blue: 1.0)
        case .aerobic:
            return .ascendAccent
        case .push:
            return Color(red: 1.0, green: 0.69, blue: 0.13)
        }
    }
}
