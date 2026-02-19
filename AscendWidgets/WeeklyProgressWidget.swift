//
//  WeeklyProgressWidget.swift
//  AscendWidgets
//
//  Created by Claude on 2/19/26.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct WeeklyProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyProgressEntry {
        WeeklyProgressEntry(date: Date(), data: .placeholder)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeeklyProgressEntry) -> Void) {
        let entry = WeeklyProgressEntry(date: Date(), data: SharedDataManager.getWidgetData())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyProgressEntry>) -> Void) {
        let currentDate = Date()
        let data = SharedDataManager.getWidgetData()
        let entry = WeeklyProgressEntry(date: currentDate, data: data)
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let data: SharedDataManager.WidgetData
}

// MARK: - Widget View

struct WeeklyProgressWidgetEntryView: View {
    var entry: WeeklyProgressProvider.Entry
    @Environment(\.widgetFamily) var family
    
    private var progressPercentage: Double {
        guard entry.data.weeklyGoalSteps > 0 else { return 0 }
        return min(Double(entry.data.weeklySteps) / Double(entry.data.weeklyGoalSteps), 1.0)
    }
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }
    
    private var smallView: some View {
        VStack(spacing: 8) {
            // Title
            Text("This Week")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: progressPercentage)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(entry.data.weeklySteps)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("steps")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            
            // Workouts count
            Text("\(entry.data.weeklyWorkoutCount) workouts")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private var mediumView: some View {
        HStack(spacing: 20) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                
                Circle()
                    .trim(from: 0, to: progressPercentage)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(progressPercentage * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("of goal")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, height: 90)
            
            // Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Progress")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 16) {
                    StatItem(
                        icon: "figure.stairs",
                        value: "\(entry.data.weeklySteps)",
                        label: "Steps",
                        color: .blue
                    )
                    
                    StatItem(
                        icon: "building.2",
                        value: "\(entry.data.weeklyFloors)",
                        label: "Floors",
                        color: .green
                    )
                    
                    StatItem(
                        icon: "checkmark.circle.fill",
                        value: "\(entry.data.weeklyWorkoutCount)",
                        label: "Workouts",
                        color: .orange
                    )
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Helper Views

private struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget Definition

struct WeeklyProgressWidget: Widget {
    let kind: String = "WeeklyProgressWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProgressProvider()) { entry in
            WeeklyProgressWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Weekly Progress")
        .description("Track your weekly steps, floors, and workouts.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    WeeklyProgressWidget()
} timeline: {
    WeeklyProgressEntry(date: Date(), data: .placeholder)
}

#Preview(as: .systemMedium) {
    WeeklyProgressWidget()
} timeline: {
    WeeklyProgressEntry(date: Date(), data: .placeholder)
}
