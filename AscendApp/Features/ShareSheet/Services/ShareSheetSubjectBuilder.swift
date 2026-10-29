import Foundation

/// Builds a `ShareSheetSubject` from the saved climb.
///
/// Every number comes from canonical data and is formatted once; the rank is the standing the
/// presenting screen froze when the climb ended, and is passed in, never derived here.
enum ShareSheetSubjectBuilder {
    /// Points kept for the heart-rate sticker's trace.
    static let heartRateTraceCount = 48

    static func make(
        workout: Workout,
        climb: Climb?,
        rankPosition: Int?,
        rankField: Int?,
        bestEfforts: [RankedBestEffort],
        measurementSystem: MeasurementSystem,
        calendar: Calendar = .current
    ) -> ShareSheetSubject {
        let metadata = LiveClimbWorkoutSummaryData.metadata(for: workout)
        let kind: ShareSheetSubject.Kind
        if climb != nil {
            kind = .landmark
        } else if metadata?.trackingMode == .routine {
            kind = .routine
        } else {
            kind = .justClimb
        }

        let title: String
        let label: String
        var landmark: ShareSheetSubject.Landmark?
        switch kind {
        case .landmark:
            let climb = climb!
            title = climb.name
            let height = landmarkHeightText(climb: climb, measurementSystem: measurementSystem)
            label = "\(climb.name.uppercased()) · \(height)"
            landmark = ShareSheetSubject.Landmark(name: climb.name, heightText: height)
        case .routine:
            title = workout.name.isEmpty ? "Routine" : workout.name
            label = title.uppercased()
        case .justClimb:
            title = "Just Climb"
            label = "JUST CLIMB"
        }

        let heartRates = workout.heartRateTimeSeries.map(\.heartRate).filter { $0 > 0 }

        return ShareSheetSubject(
            kind: kind,
            title: title,
            label: label,
            dateText: ShareSheetFormat.cardDate(workout.date, calendar: calendar),
            stepsText: ShareSheetFormat.integer(workout.steps),
            durationText: workout.durationFormatted,
            stepsPerMinuteText: ShareSheetFormat.decimal(workout.stepsPerMinute ?? 0, places: 1),
            floorsText: floorsText(workout: workout, climb: climb),
            averageHeartRate: (workout.avgHeartRate ?? 0) > 0 ? workout.avgHeartRate : nil,
            maxHeartRate: (workout.maxHeartRate ?? 0) > 0 ? workout.maxHeartRate : nil,
            heartRateTrace: downsample(heartRates.map(Double.init), to: heartRateTraceCount),
            rank: ShareSheetSubject.Rank(position: rankPosition, field: rankField),
            splits: ShareSheetSplitResolver.resolve(for: workout),
            bestEfforts: ShareSheetBestEffortResolver.resolve(bestEfforts),
            landmark: landmark
        )
    }

    /// Steps divided by 16 for any stair work; a landmark shows the share of its building's own
    /// floors the attempt covered, so a finished climb reads the number Climb Detail shows.
    static func floorsText(workout: Workout, climb: Climb?) -> String? {
        guard workout.steps > 0 else { return nil }
        if let climb, climb.calculatedFloors > 0, climb.referenceStepCount > 0 {
            let floors = Double(climb.calculatedFloors) * Double(workout.steps) / Double(climb.referenceStepCount)
            return ShareSheetFormat.integer(Int(floors.rounded()))
        }
        return ShareSheetFormat.integer(FloorsClimbed.count(forSteps: workout.steps))
    }

    static func landmarkHeightText(climb: Climb, measurementSystem: MeasurementSystem) -> String {
        switch measurementSystem {
        case .metric:
            return "\(Int(climb.referenceHeightMeters.rounded())) M"
        case .imperial:
            return "\(Int(climb.referenceHeightFeet.rounded())) FT"
        }
    }

    /// An even sample of `values`, so a long series draws as a short trace.
    static func downsample(_ values: [Double], to count: Int) -> [Double] {
        guard values.count > count, count > 1 else { return values }
        let step = Double(values.count - 1) / Double(count - 1)
        return (0..<count).map { values[Int((Double($0) * step).rounded())] }
    }
}
