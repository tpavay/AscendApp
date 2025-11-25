//
//  WorkoutSharePoster.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/5/25.
//

import SwiftUI
import UIKit

struct WorkoutSharePoster: View {
    let workout: Workout
    let usesPhotoBackground: Bool
    let backgroundImage: UIImage?
    let backgroundStyle: PosterBackgroundStyle
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    var preferredMetric: WorkoutMetric = .steps
    private let cornerRadius: CGFloat = 32
    private let accent = Color.accent
    private let photoCornerRadius: CGFloat = 24
    private let photoSize: CGFloat = 210
    private let iconContainerSize: CGFloat = 26
    private let iconSize: CGFloat = 16
    private let iconContainerSizeLarge: CGFloat = 32
    private let iconSizeLarge: CGFloat = 19

    var body: some View {
        photoSummaryCard
    }
}

private extension WorkoutSharePoster {
    var hasPhoto: Bool {
        backgroundImage != nil
    }

    var workoutTitle: String {
        workout.name.isEmpty ? "Stair workout" : workout.name
    }

    var bigLineText: String {
        return "\(workout.durationFormatted) • \(primaryMetricText)"
    }

    var condensedSecondaryLine: String? {
        let parts = [paceDisplay, verticalDisplay].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    var condensedHeartRateLine: String? {
        let parts: [String?] = [
            workout.avgHeartRate.map { "Avg \($0) BPM" },
            workout.maxHeartRate.map { "Max \($0) BPM" }
        ]
        let values = parts.compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    var paceDisplay: String? {
        guard let pace = workout.pace(for: preferredMetric) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        let paceValue = formatter.string(from: NSNumber(value: pace)) ?? String(format: "%.1f", pace)
        let unit = "\(preferredMetric.unit)/min"
        return "\(paceValue) \(unit)"
    }

    var verticalDisplay: String? {
        guard workout.steps > 0 else { return nil }
        let vertical = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = vertical < 100 ? 1 : 0
        let value = formatter.string(from: NSNumber(value: vertical)) ?? String(format: "%.0f", vertical)
        return "\(value) \(measurementSystem.distanceAbbreviation)"
    }

    var heartRateDisplay: String? {
        switch (workout.avgHeartRate, workout.maxHeartRate) {
        case let (avg?, max?):
            return "Avg \(avg) BPM • Max \(max) BPM"
        case let (avg?, nil):
            return "Avg \(avg) BPM"
        case let (nil, max?):
            return "Max \(max) BPM"
        default:
            return nil
        }
    }

    var primaryMetricText: String {
        let value = workout.metricValue(for: preferredMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formattedValue) \(preferredMetric.unit)"
    }

    var photoSummaryCard: some View {
        ZStack {
            cardBackground

            VStack(alignment: .center, spacing: hasPhoto ? 10 : 18) {
                if hasPhoto {
                    photoTile
                }

                titleView

                statList
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, hasPhoto ? 10 : 4)
            .padding(.bottom, 46)
        }
        .overlay(alignment: .bottomTrailing) {
            AscendBadge(color: .white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ShareWorkoutViewModel.displayCardHeight,
            maxHeight: ShareWorkoutViewModel.displayCardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    var cardBackground: some View {
        defaultBackground
    }

    var defaultBackground: some View {
        LinearGradient(
            colors: [.night, .jetLighter],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
    }

    var photoTile: some View {
        Image(uiImage: backgroundImage ?? UIImage())
            .resizable()
            .scaledToFill()
            .frame(width: photoSize, height: photoSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: photoCornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
    }

    var titleView: some View {
        Text(workoutTitle)
            .font(hasPhoto ? .montserratBold(size: 18) : .montserratBold(size: 22))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    var statList: some View {
        VStack(alignment: .leading, spacing: hasPhoto ? 8 : 10) {
            statRow(
                icon: "clock.arrow.circlepath",
                label: "Duration",
                value: workout.durationFormatted,
                isPR: hasPR(.longestDuration)
            )

            let prType: PersonalRecordType = preferredMetric == .steps ? .mostSteps : .mostFloors
            statRow(
                icon: preferredMetric == .steps ? "figure.stairs" : "building.2",
                label: preferredMetric.displayName,
                value: stepsDisplay,
                isPR: hasPR(prType)
            )

            if !hasPhoto {
                if let stepsPerMinute = stepsPerMinuteDisplay {
                    statRow(
                        icon: "speedometer",
                        label: stepsPerMinute.label,
                        value: stepsPerMinute.value,
                        isPR: hasPR(.highestAveragePace)
                    )
                }
            }

            if let calories = caloriesDisplay {
                statRow(
                    icon: "flame.fill",
                    label: "Calories",
                    value: calories,
                    isPR: hasPR(.mostCaloriesBurned)
                )
            }

            if !hasPhoto {
                if let maxHeartRate = maxHeartRateDisplay {
                    statRow(
                        icon: "heart.fill",
                        label: "Max Heart Rate",
                        value: maxHeartRate,
                        isPR: hasPR(.highestMaxHeartRate)
                    )
                }
            }
        }
    }
    
    // Helper to check if a PR type was achieved in this workout
    func hasPR(_ type: PersonalRecordType) -> Bool {
        return workout.achievedPersonalRecords.contains(type)
    }

}

private extension WorkoutSharePoster {
    var stepsDisplay: String {
        let metricValue = workout.metricValue(for: preferredMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: metricValue)) ?? "\(metricValue)"
        return "\(value) \(preferredMetric.unit)"
    }

    var stepsPerMinuteDisplay: (label: String, value: String)? {
        guard let pace = workout.pace(for: preferredMetric) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        let paceValue = formatter.string(from: NSNumber(value: pace)) ?? String(format: "%.1f", pace)
        let label = "\(preferredMetric.displayName) per Minute"
        let value = "\(paceValue) \(preferredMetric.unit)/min"
        return (label, value)
    }

    var maxHeartRateDisplay: String? {
        guard let maxHeartRate = workout.maxHeartRate else { return nil }
        return "\(maxHeartRate) BPM"
    }

    var statLabelFont: Font {
        hasPhoto ? .montserratMedium(size: 12) : .montserratMedium(size: 14)
    }

    var statValueFont: Font {
        hasPhoto ? .montserratBold(size: 15) : .montserratBold(size: 18)
    }

    var statIconContainerSize: CGFloat {
        hasPhoto ? iconContainerSize : iconContainerSizeLarge
    }

    var statIconSize: CGFloat {
        hasPhoto ? iconSize : iconSizeLarge
    }

    var caloriesDisplay: String? {
        guard let calories = workout.caloriesBurned else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: calories)) ?? "\(calories)"
        return "\(value) cal"
    }

    func statRow(icon: String, label: String, value: String, isPR: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.1))
                    .frame(width: statIconContainerSize, height: statIconContainerSize)
                Image(systemName: icon)
                    .font(.system(size: statIconSize, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(statLabelFont)
                    .foregroundStyle(.white.opacity(0.8))
                
                HStack(spacing: 6) {
                    Text(value)
                        .font(statValueFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    if isPR {
                        Text("(PR)")
                            .font(hasPhoto ? .montserratBold(size: 12) : .montserratBold(size: 14))
                            .foregroundStyle(Color.orange)
                            .shadow(color: Color.orange.opacity(0.5), radius: 2, x: 0, y: 0)
                    }
                }
            }
        }
    }
}

#if DEBUG
struct WorkoutSharePoster_Previews: PreviewProvider {
    static let sampleWorkout = Workout(
        name: "Stair Climbing Workout",
        duration: 15 * 60 + 9,
        steps: 1_550,
        floors: 97,
        stepsPerFloor: 16,
        caloriesBurned: 200
    )

    static let samplePhoto = UIImage(named: "Image")

    static var previews: some View {
        Group {
            poster(style: .defaultStyle)
                .previewDisplayName("Default")
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .background(Color(.systemBackground))
    }

    private static func poster(style: PosterBackgroundStyle) -> some View {
        WorkoutSharePoster(
            workout: sampleWorkout,
            usesPhotoBackground: true,
            backgroundImage: samplePhoto,
            backgroundStyle: style,
            measurementSystem: .imperial,
            stepHeight: 0.18
        )
        .frame(
            width: ShareWorkoutViewModel.displayCardWidth,
            height: ShareWorkoutViewModel.displayCardHeight
        )
    }
}
#endif

private struct AscendBadge: View {
    var color: Color = .white.opacity(0.9)
    var iconSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            Image("AppIconInternal")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(color)
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            Text("Ascend")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(color)
        }
    }
}

enum PosterBackgroundStyle: String, CaseIterable, Identifiable {
    case defaultStyle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultStyle:
            return "Default"
        }
    }
}
