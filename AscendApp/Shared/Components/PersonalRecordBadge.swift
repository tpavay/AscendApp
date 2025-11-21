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
        HStack(spacing: 4) {
            Text(recordType.emoji)
                .font(.system(size: size.emojiSize))
            
            Text("PR")
                .font(.system(size: size.fontSize, weight: .bold))
                .foregroundColor(.white)
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
        .cornerRadius(size.padding * 2)
        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

/// A view that displays all PR badges for a workout
struct PersonalRecordBadgeGroup: View {
    let workout: Workout
    let size: PersonalRecordBadge.BadgeSize
    let maxVisible: Int?
    
    init(
        workout: Workout,
        size: PersonalRecordBadge.BadgeSize = .medium,
        maxVisible: Int? = nil
    ) {
        self.workout = workout
        self.size = size
        self.maxVisible = maxVisible
    }
    
    var body: some View {
        let records = workout.achievedPersonalRecords
        
        if records.isEmpty {
            EmptyView()
        } else {
            let displayRecords = maxVisible.map { Array(records.prefix($0)) } ?? records
            let remainingCount = records.count - displayRecords.count
            
            HStack(spacing: 6) {
                ForEach(displayRecords, id: \.rawValue) { recordType in
                    PersonalRecordBadge(recordType: recordType, size: size)
                }
                
                if remainingCount > 0 {
                    Text("+\(remainingCount)")
                        .font(.system(size: size.fontSize, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, size.padding)
                        .padding(.vertical, size.padding * 0.5)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(size.padding)
                }
            }
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

