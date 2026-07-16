import Foundation

/// The three live effort zones shown while climbing.
///
/// Product-defined absolute bands over percent of estimated max heart rate —
/// deliberately NOT a per-user calibrated effort model (see CLAUDE.md →
/// Workout Measurement). Blue is conversational effort, green is aerobic work,
/// amber is pushing hard.
enum HeartRateZone: String, CaseIterable, Sendable {
    case recovery
    case aerobic
    case push

    var displayName: String {
        switch self {
        case .recovery:
            return "Recovery"
        case .aerobic:
            return "Aerobic"
        case .push:
            return "Push"
        }
    }
}

/// Resolves a heart-rate reading into a zone for a given climber.
struct HeartRateZoneProfile: Equatable, Sendable {
    /// Upper bound of the recovery (blue) zone as a fraction of max HR.
    static let recoveryUpperFraction = 0.70
    /// Upper bound of the aerobic (green) zone as a fraction of max HR.
    static let aerobicUpperFraction = 0.85

    /// Used when the profile has no age (age is optional pre-onboarding).
    static let fallbackAge = 35

    let maxHeartRate: Int

    /// Estimated max HR from age using the Tanaka formula (208 − 0.7 × age),
    /// which tracks measured max HR better than 220 − age across age groups.
    init(age: Int?) {
        let boundedAge = min(max(age ?? Self.fallbackAge, 13), 120)
        maxHeartRate = Int((208.0 - 0.7 * Double(boundedAge)).rounded())
    }

    func zone(forBeatsPerMinute beatsPerMinute: Int) -> HeartRateZone {
        let fraction = Double(beatsPerMinute) / Double(maxHeartRate)
        if fraction < Self.recoveryUpperFraction {
            return .recovery
        }
        if fraction < Self.aerobicUpperFraction {
            return .aerobic
        }
        return .push
    }
}
