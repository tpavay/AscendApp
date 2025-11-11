//
//  LeaderboardFilterBar.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardFilterBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedMetric: LeaderboardMetric
    @Binding var selectedTimeFrame: LeaderboardTimeFrame

    var body: some View {
        VStack(spacing: 16) {
            // Metric selector - Horizontal scroll at top
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(LeaderboardMetric.allCases) { metric in
                        MetricChip(
                            metric: metric,
                            isSelected: selectedMetric == metric,
                            action: {
                                selectedMetric = metric
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }

            // Time frame selector - Smaller, below metrics
            HStack(spacing: 8) {
                ForEach(LeaderboardTimeFrame.allCases) { timeFrame in
                    TimeFrameChip(
                        timeFrame: timeFrame,
                        isSelected: selectedTimeFrame == timeFrame,
                        action: {
                            selectedTimeFrame = timeFrame
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct MetricChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let metric: LeaderboardMetric
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: metric.icon)
                    .font(.system(size: 24))

                Text(metric.shortName)
                    .font(.montserratMedium(size: 14))
            }
            .foregroundStyle(isSelected ? .white : (colorScheme == .dark ? .white.opacity(0.6) : .gray))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accent : (colorScheme == .dark ? Color("Jet") : Color.white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : (colorScheme == .dark ? Color.white.opacity(0.2) : Color.gray.opacity(0.3)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TimeFrameChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let timeFrame: LeaderboardTimeFrame
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(timeFrame.shortName)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(isSelected ? .white : (colorScheme == .dark ? .white.opacity(0.6) : .gray))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accent : (colorScheme == .dark ? Color("Jet").opacity(0.5) : Color.gray.opacity(0.1)))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LeaderboardFilterBar(
        selectedMetric: .constant(.steps),
        selectedTimeFrame: .constant(.weekly)
    )
    .padding()
    .themedBackground()
}
