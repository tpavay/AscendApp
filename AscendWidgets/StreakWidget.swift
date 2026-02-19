//
//  StreakWidget.swift
//  AscendWidgets
//
//  Created by Claude on 2/19/26.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), data: .placeholder)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let entry = StreakEntry(date: Date(), data: SharedDataManager.getWidgetData())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let currentDate = Date()
        let data = SharedDataManager.getWidgetData()
        let entry = StreakEntry(date: currentDate, data: data)
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct StreakEntry: TimelineEntry {
    let date: Date
    let data: SharedDataManager.WidgetData
}

// MARK: - Widget View

struct StreakWidgetEntryView: View {
    var entry: StreakProvider.Entry
    @Environment(\.widgetFamily) var family
    
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
            // Flame icon
            Image(systemName: "flame.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            
            // Streak count
            Text("\(entry.data.currentStreak)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            // Label
            Text(entry.data.currentStreak == 1 ? "Day Streak" : "Day Streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private var mediumView: some View {
        HStack(spacing: 20) {
            // Streak info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    
                    Text("\(entry.data.currentStreak)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }
                
                Text("Day Streak")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if let lastWorkout = entry.data.lastWorkoutDate {
                    Text("Last: \(lastWorkout, style: .relative) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Weekly stats
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.stairs")
                        .font(.system(size: 14))
                    Text("\(entry.data.weeklySteps)")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.accent)
                
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.system(size: 14))
                    Text("\(entry.data.weeklyFloors)")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.green)
                
                Text("This Week")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Definition

struct StreakWidget: Widget {
    let kind: String = "StreakWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Workout Streak")
        .description("Track your consecutive workout days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: Date(), data: .placeholder)
}

#Preview(as: .systemMedium) {
    StreakWidget()
} timeline: {
    StreakEntry(date: Date(), data: .placeholder)
}
