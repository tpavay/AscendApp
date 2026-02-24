//
//  TemplateMediaCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/19/25.
//

import SwiftUI
import UIKit

/// Card that displays a remote template background with workout stats overlay at bottom
struct TemplateMediaCard: View {
    let workout: Workout
    let image: UIImage?
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    let preferredMetric: WorkoutMetric
    let displayName: String

    private let cornerRadius: CGFloat = 32

    // MARK: - Weight Formatting

    private var formattedTotalWeight: String? {
        guard workout.hasWeights else { return nil }
        let weight = workout.totalWeightUsed
        let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
            ? weight.formatted(.number.precision(.fractionLength(0)))
            : weight.formatted(.number.precision(.fractionLength(1)))
        return "+\(formatted) \(measurementSystem.weightAbbreviation)"
    }

    var body: some View {
        ZStack {
            // Template background
            if let image = image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                // Placeholder gradient while loading
                LinearGradient(
                    colors: [.night, .jetLighter],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Top gradient overlay for stats
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer()

                // Bottom gradient for branding
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
            }

            // Stats layout
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    // Left: Stats
                    VStack(alignment: .leading, spacing: 2) {
                        // Workout title
                        if !workout.name.isEmpty {
                            Text(workout.name)
                                .font(.montserratSemiBold(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }

                        // Primary metric: value + label
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(formattedPrimaryMetricValue)
                                .font(.montserratBold(size: 44))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)

                            Text(preferredMetric.displayName)
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        // Secondary stats row
                        HStack(spacing: 12) {
                            // Duration
                            HStack(spacing: 5) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.accent)
                                Text(workout.durationFormatted)
                                    .font(.montserratSemiBold(size: 13))
                                    .foregroundStyle(.white.opacity(0.9))
                            }

                            // Pace
                            if let pace = workout.pace(for: preferredMetric) {
                                HStack(spacing: 5) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.accent)
                                    Text("\(formattedPaceValue(pace)) \(paceLabel)")
                                        .font(.montserratSemiBold(size: 13))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }

                            // Added Weight
                            if let weightText = formattedTotalWeight {
                                HStack(spacing: 5) {
                                    Image(systemName: "dumbbell.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.accent)
                                    Text(weightText)
                                        .font(.montserratSemiBold(size: 13))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    Spacer()

                    // Right: PRs badge (if any, including weight PRs)
                    if workout.totalPRCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(workout.totalPRCount)")
                                .font(.montserratBold(size: 16))
                                .foregroundStyle(.white)
                            Image(systemName: "medal.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.4))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                // Branding at bottom
                HStack {
                    AscendBadge(color: .white.opacity(0.9))
                    Spacer()
                    if !displayName.isEmpty {
                        Text("@\(displayName)")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(
            width: WorkoutShareCarouselViewModel.displayCardWidth,
            height: WorkoutShareCarouselViewModel.displayCardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func secondaryStat(value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)
            Text(label)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Formatted Values

    private var formattedPrimaryMetricValue: String {
        let value = workout.metricValue(for: preferredMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var formattedSecondaryMetricValue: String {
        // Show the other metric (if steps is primary, show floors and vice versa)
        let secondaryMetric: WorkoutMetric = preferredMetric == .steps ? .floors : .steps
        let value = workout.metricValue(for: secondaryMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var secondaryMetricLabel: String {
        preferredMetric == .steps ? "Floors" : "Steps"
    }

    private func formattedPaceValue(_ pace: Double) -> String {
        pace.formatted(.number.precision(.fractionLength(1)))
    }

    private var paceLabel: String {
        switch preferredMetric {
        case .steps:
            return "spm"
        case .floors:
            return "fpm"
        }
    }
}

#Preview {
    TemplateMediaCard(
        workout: Workout(
            name: "Morning Stair Climb",
            duration: 1800,
            steps: 2500,
            floors: 156,
            stepsPerFloor: 16,
            avgHeartRate: 145,
            maxHeartRate: 165,
            caloriesBurned: 320
        ),
        image: nil,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        preferredMetric: .steps,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}
