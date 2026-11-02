//
//  BestEffortTrophyBadge.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// A compact trophy icon + count badge for the Best Efforts earned by a workout.
struct BestEffortTrophyBadge: View {
    let bestEfforts: [RankedBestEffort]

    @State private var showingDetails = false

    private var primaryColor: Color {
        bestEfforts.first?.trophyColor ?? .accent
    }

    var body: some View {
        if !bestEfforts.isEmpty {
            Button {
                showingDetails = true
            } label: {
                HStack(spacing: 5) {
                    trophyIcons

                    Text("\(bestEfforts.count)")
                        .font(.montserratSemiBold(size: 13))
                }
                .foregroundStyle(primaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .stroke(primaryColor, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDetails) {
                detailsPopover
            }
        }
    }

    private var trophyIcons: some View {
        HStack(spacing: bestEfforts.count > 1 ? -3 : 0) {
            ForEach(Array(bestEfforts.prefix(3).enumerated()), id: \.element.id) { _, effort in
                AppIcon(token: .bestEffortTrophy, pointSize: 13, weight: .semibold)
                    .foregroundStyle(effort.trophyColor)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
            }
        }
    }

    private var detailsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Best Efforts")
                    .font(.montserratSemiBold(size: 15))
                    .padding(.bottom, 2)

                ForEach(bestEfforts) { effort in
                    HStack(alignment: .top, spacing: 9) {
                        AppIcon(token: .bestEffortTrophy, pointSize: 16, weight: .semibold)
                            .foregroundStyle(effort.trophyColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(effort.sentence)
                                .font(.montserratSemiBold(size: 12))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(effort.valueText) | \(effort.detailText)")
                                .font(.montserratRegular(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: 310, maxHeight: 380)
        .presentationCompactAdaptation(.popover)
    }
}

#Preview {
    let workout = Workout(
        name: "Weighted climb",
        duration: 1_800,
        steps: 3_000,
        floors: 188,
        source: .headphoneMotion,
        weightConfiguration: WeightConfiguration(entries: [
            WeightEntry(equipmentType: .weightedVest, weightValue: 20)
        ])
    )
    let performance = BestEffortPerformance(
        metric: .mostSteps,
        workout: workout,
        value: 3_000,
        steps: 3_000,
        duration: 1_800,
        segmentStartElapsedSeconds: nil,
        segmentEndElapsedSeconds: nil
    )

    BestEffortTrophyBadge(
        bestEfforts: [
            RankedBestEffort(
                metric: .mostSteps,
                rank: 1,
                scope: .allTime,
                context: .weighted,
                performance: performance
            )
        ]
    )
    .padding()
    .preferredColorScheme(.dark)
}
