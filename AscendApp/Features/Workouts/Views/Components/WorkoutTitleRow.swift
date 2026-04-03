//
//  WorkoutTitleRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Describes the weight summary for display in the title row subtitle.
enum WeightSummary {
    /// Single weight source (e.g. "20 lb vest")
    case single(label: String)
    /// Multiple weight sources with total and per-entry breakdown
    case multiple(total: String, entries: [(name: String, weight: String)])
    /// No weights used
    case none
}

/// Workout title row with left-aligned name, date + weight subtitle, and trailing PR trophy badge.
struct WorkoutTitleRow: View {
    let workoutName: String
    let dateText: String
    let weightSummary: WeightSummary
    let prCount: Int
    let prDetails: [PRDetail]
    let effectiveColorScheme: ColorScheme

    @State private var showingWeightBreakdown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Leading: name + subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutName)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                subtitleView
            }

            Spacer(minLength: 4)

            // Trailing: PR trophy badge
            if prCount > 0 {
                PRTrophyBadge(count: prCount, details: prDetails)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch weightSummary {
        case .none:
            Text(dateText)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)

        case .single(let label):
            Text("\(dateText) | \(label)")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)

        case .multiple(let total, _):
            Button {
                showingWeightBreakdown = true
            } label: {
                HStack(spacing: 2) {
                    Text("\(dateText) | +\(total)")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingWeightBreakdown) {
                weightBreakdownPopover
            }
        }
    }

    @ViewBuilder
    private var weightBreakdownPopover: some View {
        if case .multiple(let total, let entries) = weightSummary {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weight Breakdown")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.name)
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        Spacer()
                        Text(entry.weight)
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    Spacer()
                    Text(total)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
            }
            .padding(16)
            .frame(minWidth: 220)
            .presentationCompactAdaptation(.popover)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        WorkoutTitleRow(
            workoutName: "Afternoon stair stepper",
            dateText: "Mar 27 at 3:54 PM",
            weightSummary: .single(label: "20 lb vest"),
            prCount: 4,
            prDetails: [],
            effectiveColorScheme: .dark
        )

        WorkoutTitleRow(
            workoutName: "Morning climb session",
            dateText: "Today at 9:15 AM",
            weightSummary: .multiple(
                total: "30 lb",
                entries: [
                    (name: "Weighted Vest", weight: "20 lb"),
                    (name: "Dumbbells", weight: "10 lb")
                ]
            ),
            prCount: 2,
            prDetails: [],
            effectiveColorScheme: .dark
        )

        WorkoutTitleRow(
            workoutName: "Evening session",
            dateText: "Yesterday at 6:00 PM",
            weightSummary: .none,
            prCount: 0,
            prDetails: [],
            effectiveColorScheme: .dark
        )
    }
    .padding(20)
    .background(Color.black)
}
