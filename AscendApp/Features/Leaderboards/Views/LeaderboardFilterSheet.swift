//
//  LeaderboardFilterSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared

    @Binding var selectedTimeFrame: LeaderboardTimeFrame
    @Binding var selectedMetric: LeaderboardMetric
    let allowsMetricSelection: Bool

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Filters")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text("Choose how to view the leaderboard")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TIME FRAME")
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(LeaderboardTimeFrame.allCases) { timeFrame in
                                LeaderboardFilterOptionRow(
                                    title: timeFrame.displayName,
                                    isSelected: selectedTimeFrame == timeFrame
                                ) {
                                    HapticsManager.shared.trigger(.selection)
                                    selectedTimeFrame = timeFrame
                                }
                            }
                        }
                    }

                    if allowsMetricSelection {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("METRIC")
                                .font(.montserratSemiBold(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 8) {
                                ForEach(LeaderboardMetric.allCases) { metric in
                                    LeaderboardFilterOptionRow(
                                        title: metric.displayName(for: preferredMetric),
                                        isSelected: selectedMetric == metric
                                    ) {
                                        HapticsManager.shared.trigger(.selection)
                                        selectedMetric = metric
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 32)
        .padding(.bottom, 12)
        .appSheetStyle(.filterMenu(height: 520))
    }
}

private struct LeaderboardFilterOptionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LeaderboardFilterSheet(
        selectedTimeFrame: .constant(.weekly),
        selectedMetric: .constant(.climb),
        allowsMetricSelection: true
    )
}
