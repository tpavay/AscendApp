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

    var body: some View {
        photoSummaryCard
    }
}

private extension WorkoutSharePoster {
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
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                photoBackground
                    .clipped()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 32))

                VStack(alignment: .leading, spacing: 10) {
                    Text(bigLineText)
                        .font(.montserratBold(size: 30))
                        .foregroundStyle(.white)

                    if let condensedSecondaryLine {
                        Text(condensedSecondaryLine)
                            .font(.montserratMedium(size: 16))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    if let condensedHeartRateLine {
                        Text(condensedHeartRateLine)
                            .font(.montserratMedium(size: 16))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer().frame(height: 8)

                    AscendBadge(color: .white.opacity(0.9))
                }
                .padding(30)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ShareWorkoutViewModel.displayCardHeight, maxHeight: ShareWorkoutViewModel.displayCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }

    var photoBackground: some View {
        Group {
            if usesPhotoBackground, let image = backgroundImage {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    }
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "1A1A1A"),
                        Color(hex: "050505")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

}

private struct AscendBadge: View {
    var color: Color = .white.opacity(0.9)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(180))
            Text("Ascend")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(color)
        }
    }
}
