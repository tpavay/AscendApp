import Foundation

struct UserBaselineService {
    struct Result {
        let detectedLevel: Int
        let autoCalibratedLevel: Int
        let validWorkoutCount: Int
    }

    static func calculateBaseline(from workouts: [Workout], seededLevel: Int) -> Result? {
        let validSPMValues = validSPMValues(from: workouts)
        guard validSPMValues.count >= 3 else { return nil }

        let sortedValues = validSPMValues.sorted()
        let trimmedStartIndex = Int(Double(sortedValues.count) * 0.4)
        let topValues = Array(sortedValues[trimmedStartIndex...])
        let medianSPM = median(of: topValues)
        let detectedLevel = SPMMappingService.level(forSPM: medianSPM)
        let blendRatio = max(0, min(1, Double(validSPMValues.count - 3) / 7.0))
        let blendedLevel = Int(
            (
                Double(SPMMappingService.clampedLevel(seededLevel)) * (1 - blendRatio)
                + Double(detectedLevel) * blendRatio
            ).rounded()
        )

        return Result(
            detectedLevel: detectedLevel,
            autoCalibratedLevel: SPMMappingService.clampedLevel(blendedLevel),
            validWorkoutCount: validSPMValues.count
        )
    }

    static func validSPMValues(from workouts: [Workout]) -> [Double] {
        workouts.compactMap { workout in
            guard let stepsPerMinute = workout.stepsPerMinute else { return nil }
            guard workout.duration >= 300,
                  WorkoutPlausibilityPolicy.hasPlausibleTotals(workout),
                  stepsPerMinute < 190,
                  !workout.hasWeights else { return nil }
            return stepsPerMinute
        }
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return Double(SPMMappingService.spm(forLevel: 7)) }

        let middleIndex = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middleIndex - 1] + values[middleIndex]) / 2
        }
        return values[middleIndex]
    }
}
