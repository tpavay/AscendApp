//
//  WorkoutSharePoster.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/5/25.
//

import SwiftUI

struct WorkoutSharePoster: View {
    let workout: Workout
    let usesPhotoBackground: Bool
    let backgroundImage: UIImage?
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    private let cornerRadius: CGFloat = 32
    private let accent = Color.accent
    private let photoCornerRadius: CGFloat = 26
    private let photoSize: CGFloat = 200
    private let iconContainerSize: CGFloat = 38
    private let topPadding: CGFloat = 26

    var body: some View {
        photoSummaryCard
    }
}

private extension WorkoutSharePoster {
    var hasPhoto: Bool {
        usesPhotoBackground && backgroundImage != nil
    }

    var workoutTitle: String {
        workout.name.isEmpty ? "Stair workout" : workout.name
    }

    var bigLineText: String {
        guard let metricText = primaryMetricText else {
            return workout.durationFormatted
        }
        return "\(workout.durationFormatted) • \(metricText)"
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
        guard let pace = workout.pace else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        let paceValue = formatter.string(from: NSNumber(value: pace)) ?? String(format: "%.1f", pace)
        let unit = workout.metricType == .steps ? "steps/min" : "floors/min"
        return "\(paceValue) \(unit)"
    }

    var verticalDisplay: String? {
        guard let vertical = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        ) else {
            return nil
        }
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

    var primaryMetricText: String? {
        guard let value = workout.primaryMetricValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        switch workout.metricType {
        case .steps:
            return "\(formattedValue) steps"
        case .floors:
            return "\(formattedValue) floors"
        }
    }

    var photoSummaryCard: some View {
        ZStack {
            cardBackground

            VStack(alignment: .leading, spacing: hasPhoto ? 12 : 10) {
                if hasPhoto {
                    Spacer().frame(height: topPadding)
                    photoTile
                        .frame(height: photoSize)
                    titleView
                } else {
                    titleView
                }

                statList
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .overlay(alignment: .bottomTrailing) {
            AscendBadge(color: .white.opacity(0.9))
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ShareWorkoutViewModel.displayCardHeight,
            maxHeight: ShareWorkoutViewModel.displayCardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    var cardBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: "111116"),
                Color(hex: "060607")
            ],
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
            .font(.montserratBold(size: 22))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
    }

    var statList: some View {
        VStack(alignment: .leading, spacing: 14) {
            statRow(icon: "clock.arrow.circlepath", label: "Workout Duration", value: workout.durationFormatted)

            if let stepsValue = stepsDisplay {
                statRow(icon: "figure.walk.motion", label: "Steps", value: stepsValue)
            }

            if let calories = caloriesDisplay {
                statRow(icon: "flame.fill", label: "Calories", value: calories)
            }
        }
    }

}

private extension WorkoutSharePoster {
    var stepsDisplay: String? {
        guard let steps = workout.steps else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        return "\(value) steps"
    }

    var caloriesDisplay: String? {
        guard let calories = workout.caloriesBurned else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: calories)) ?? "\(calories)"
        return "\(value) cal"
    }

    func statRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.1))
                    .frame(width: iconContainerSize, height: iconContainerSize)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                Text(value)
                    .font(.montserratBold(size: 19))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }
}

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
