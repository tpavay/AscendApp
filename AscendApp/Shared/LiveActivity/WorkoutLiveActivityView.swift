//
//  WorkoutLiveActivityView.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity Widget for workout tracking
/// Shows on lock screen and Dynamic Island during active workout
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock screen / banner view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long press)
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }
            } compactLeading: {
                // Compact left side
                CompactLeadingView(context: context)
            } compactTrailing: {
                // Compact right side
                CompactTrailingView(context: context)
            } minimal: {
                // Minimal view (when multiple activities)
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side - Duration
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.stair.stepper")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.accent)
                    
                    Text(context.attributes.workoutName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                Text(context.state.formattedDuration)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                
                if let weight = context.attributes.weightDescription {
                    Text(weight)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Right side - Stats
            VStack(alignment: .trailing, spacing: 8) {
                StatRow(
                    icon: "figure.stairs",
                    value: context.state.formattedSteps,
                    label: "steps"
                )
                
                StatRow(
                    icon: "building.2",
                    value: "\(context.state.floors)",
                    label: "floors"
                )
                
                if let hr = context.state.currentHeartRate {
                    StatRow(
                        icon: "heart.fill",
                        value: "\(hr)",
                        label: "bpm",
                        color: .red
                    )
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.8))
        .activityBackgroundTint(Color.black.opacity(0.8))
    }
}

private struct StatRow: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .accent
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dynamic Island Views

private struct CompactLeadingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.stair.stepper")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.accent)
            
            Text(context.state.formattedDuration)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        Text(context.state.formattedSteps)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.accent)
            .contentTransition(.numericText())
    }
}

private struct MinimalView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        Image(systemName: "figure.stair.stepper")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.accent)
    }
}

// MARK: - Expanded Dynamic Island Views

private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Duration")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            
            Text(context.state.formattedDuration)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
    }
}

private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Steps")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            
            Text(context.state.formattedSteps)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.accent)
                .contentTransition(.numericText())
        }
    }
}

private struct ExpandedCenterView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.stair.stepper")
                .foregroundStyle(.accent)
            
            Text(context.attributes.workoutName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }
}

private struct ExpandedBottomView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    
    var body: some View {
        HStack(spacing: 20) {
            // Floors
            VStack(spacing: 2) {
                Image(systemName: "building.2")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                
                Text("\(context.state.floors)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                
                Text("floors")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            // SPM
            if let spm = context.state.currentSPM {
                VStack(spacing: 2) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    
                    Text(String(format: "%.0f", spm))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    
                    Text("SPM")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Heart Rate
            if let hr = context.state.currentHeartRate {
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                    
                    Text("\(hr)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    
                    Text("bpm")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Calories
            if let cal = context.state.calories {
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    
                    Text("\(cal)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    
                    Text("kcal")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: WorkoutActivityAttributes(
    workoutName: "Morning Climb",
    startTime: Date(),
    hasWeightEquipment: true,
    weightDescription: "20lb vest"
)) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        elapsedSeconds: 1847,
        steps: 3250,
        floors: 27,
        currentHeartRate: 142,
        calories: 380,
        currentSPM: 78
    )
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: WorkoutActivityAttributes(
    workoutName: "Workout",
    startTime: Date(),
    hasWeightEquipment: false,
    weightDescription: nil
)) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        elapsedSeconds: 1230,
        steps: 2100,
        floors: 18,
        currentHeartRate: 135,
        calories: nil,
        currentSPM: 72
    )
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: WorkoutActivityAttributes(
    workoutName: "Evening Session",
    startTime: Date(),
    hasWeightEquipment: true,
    weightDescription: "Ankle weights"
)) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        elapsedSeconds: 2500,
        steps: 4200,
        floors: 35,
        currentHeartRate: 155,
        calories: 520,
        currentSPM: 85
    )
}
