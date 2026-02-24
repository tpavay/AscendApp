//
//  PersonalRecordBadge.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import SwiftUI

/// A badge component that displays personal record achievements
struct PersonalRecordBadge: View {
    let recordType: PersonalRecordType
    let size: BadgeSize
    @State private var showingTooltip = false
    
    enum BadgeSize {
        case small
        case medium
        case large
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 14
            case .large: return 16
            }
        }
        
        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
        
        var emojiSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            }
        }
    }
    
    init(recordType: PersonalRecordType, size: BadgeSize = .medium) {
        self.recordType = recordType
        self.size = size
    }
    
    var body: some View {
        Button {
            HapticsManager.shared.trigger(.lightImpact)
            showingTooltip = true
        } label: {
        HStack(spacing: 4) {
            Text(recordType.emoji)
                .font(.system(size: size.emojiSize))
            
            Text("PR")
                .font(.system(size: size.fontSize, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, size.padding * 1.5)
        .padding(.vertical, size.padding)
        .background(
            LinearGradient(
                colors: [Color.orange, Color.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(.rect(cornerRadius: size.padding * 2))
        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingTooltip, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                Text(recordType.emoji)
                    .font(.system(size: 32))
                Text(recordType.displayName)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A view that displays all PR badges for a workout
struct PersonalRecordBadgeGroup: View {
    let workout: Workout
    let size: PersonalRecordBadge.BadgeSize
    let maxVisible: Int?
    let respectMetricPreference: Bool
    
    @State private var settingsManager = SettingsManager.shared
    
    init(
        workout: Workout,
        size: PersonalRecordBadge.BadgeSize = .medium,
        maxVisible: Int? = nil,
        respectMetricPreference: Bool = true
    ) {
        self.workout = workout
        self.size = size
        self.maxVisible = maxVisible
        self.respectMetricPreference = respectMetricPreference
    }
    
    /// Filters records to show only the preferred steps/floors metric
    private var filteredRecords: [PersonalRecordType] {
        let records = workout.achievedPersonalRecords
        
        guard respectMetricPreference else {
            return records
        }
        
        // Filter based on user's preferred metric - show only steps OR floors, not both
        return records.filter { recordType in
            switch recordType {
            case .mostSteps:
                return settingsManager.preferredWorkoutMetric == .steps
            case .mostFloors:
                return settingsManager.preferredWorkoutMetric == .floors
            default:
                return true
            }
        }
    }
    
    var body: some View {
        let records = filteredRecords
        
        if records.isEmpty {
            EmptyView()
        } else if maxVisible != nil {
            // Limited display with +N indicator (for list views)
            let displayRecords = maxVisible.map { Array(records.prefix($0)) } ?? records
            let remainingCount = records.count - displayRecords.count
            
            HStack(spacing: 6) {
                ForEach(displayRecords, id: \.rawValue) { recordType in
                    PersonalRecordBadge(recordType: recordType, size: size)
                }
                
                if remainingCount > 0 {
                    Text("+\(remainingCount)")
                        .font(.system(size: size.fontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, size.padding)
                        .padding(.vertical, size.padding * 0.5)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(.rect(cornerRadius: size.padding))
                }
            }
        } else {
            // Horizontal scroll for full display (for detail views)
            // Extends edge-to-edge to show partial badges at screen edges
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(records, id: \.rawValue) { recordType in
                        PersonalRecordBadge(recordType: recordType, size: size)
                    }
                }
                .padding(.horizontal, 20) // Match parent container padding for content alignment
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20) // Extend scroll view to screen edges
        }
    }
}

#Preview("Single PR Badge") {
    VStack(spacing: 20) {
        PersonalRecordBadge(recordType: .mostSteps, size: .small)
        PersonalRecordBadge(recordType: .longestDuration, size: .medium)
        PersonalRecordBadge(recordType: .highestAveragePace, size: .large)
    }
    .padding()
}

