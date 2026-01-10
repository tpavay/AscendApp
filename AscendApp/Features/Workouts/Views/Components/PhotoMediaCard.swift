//
//  PhotoMediaCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import SwiftUI
import UIKit

/// Card that displays the workout's highlighted photo/video with stats overlay
struct PhotoMediaCard: View {
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
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
        return "+\(formatted) \(measurementSystem.weightAbbreviation)"
    }

    var body: some View {
        ZStack {
            // Photo background
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: WorkoutShareCarouselViewModel.displayCardWidth,
                        height: WorkoutShareCarouselViewModel.displayCardHeight
                    )
                    .clipped()
            } else {
                // Placeholder while loading
                LinearGradient(
                    colors: [.night, .jetLighter],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Top gradient overlay for stats
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.7), .black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                
                Spacer()
                
                // Bottom gradient for branding
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
            }
            
            // Stats overlay at top
            VStack {
                statsRow
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
                .padding(.bottom, 12)
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
    
    private var statsRow: some View {
        HStack(spacing: 0) {
            // Duration
            statItem(label: "Duration", value: workout.durationFormatted)

            Spacer()

            // Primary metric (Steps/Floors)
            statItem(
                label: preferredMetric.displayName,
                value: formattedMetricValue
            )

            // Added Weight (if any)
            if let weightText = formattedTotalWeight {
                Spacer()

                statItem(
                    label: "Weight",
                    value: weightText
                )
            }

            Spacer()

            // Records (if any, including weight PRs) or Pace
            if workout.totalPRCount > 0 {
                statItem(
                    label: "Records",
                    value: "\(workout.totalPRCount)",
                    showPRBadge: true
                )
            } else {
                // Show pace instead
                if let pace = workout.pace(for: preferredMetric) {
                    statItem(
                        label: paceLabel,
                        value: formattedPaceValue(pace)
                    )
                }
            }
        }
    }
    
    private func statItem(label: String, value: String, showPRBadge: Bool = false) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.85))
            
            HStack(spacing: 4) {
                Text(value)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.white)
                
                if showPRBadge {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
            }
        }
    }
    
    private var formattedMetricValue: String {
        let value = workout.metricValue(for: preferredMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private var paceLabel: String {
        preferredMetric == .steps ? "Steps/Min" : "Floors/Min"
    }
    
    private func formattedPaceValue(_ pace: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: pace)) ?? String(format: "%.0f", pace)
    }
}

#Preview {
    PhotoMediaCard(
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

