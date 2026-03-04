//
//  LeaderboardFilterBar.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardFilterBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var selectedMetric: LeaderboardMetric
    @Binding var selectedTimeFrame: LeaderboardTimeFrame
    let resetStatusText: String

    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var showFilterSheet = false
    @State private var settingsManager = SettingsManager.shared

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var filterPillText: String {
        "\(selectedTimeFrame.displayName) · \(selectedMetric.displayName(for: preferredMetric))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main filter row
            HStack(spacing: 12) {
                // Reset text (left)
                Text(resetStatusText)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(1)

                Spacer()

                // Search icon button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSearchExpanded.toggle()
                        if isSearchExpanded {
                            isSearchFocused = true
                        } else {
                            searchText = ""
                            isSearchFocused = false
                        }
                    }
                    HapticsManager.shared.trigger(.lightImpact)
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                // Combined filter pill
                Button {
                    showFilterSheet = true
                    HapticsManager.shared.trigger(.lightImpact)
                } label: {
                    HStack(spacing: 6) {
                        Text(filterPillText)
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color("Jet") : Color.white)
                    )
                    .overlay(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Expandable search field
            if isSearchExpanded {
                searchField
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isSearchFocused = false
                } label: {
                    Text("Done")
                        .font(.montserratSemiBold(size: 16))
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            LeaderboardFilterSheet(
                selectedTimeFrame: $selectedTimeFrame,
                selectedMetric: $selectedMetric,
                allowsMetricSelection: true
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search for a player", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.montserratRegular(size: 14))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Filter Sheet

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
            // Header
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
                    // Time Frame Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TIME FRAME")
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(LeaderboardTimeFrame.allCases) { timeFrame in
                                FilterOptionRow(
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
                                    FilterOptionRow(
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

            // Done button
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
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
    }
}

private struct FilterOptionRow: View {
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
                    .foregroundStyle(isSelected ? Color.accent : .secondary)
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
    LeaderboardFilterBar(
        searchText: .constant(""),
        selectedMetric: .constant(.climb),
        selectedTimeFrame: .constant(.weekly),
        resetStatusText: "Leaderboard resets in 2 days"
    )
    .padding()
    .themedBackground()
}
