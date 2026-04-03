//
//  PRTrophyBadge.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// A single PR entry for display in the trophy badge popover.
struct PRDetail: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let isWeightPR: Bool
}

/// A compact trophy icon + PR count badge outlined in accent green.
/// Tapping shows a popover listing all personal records.
struct PRTrophyBadge: View {
    let count: Int
    let details: [PRDetail]

    @State private var showingDetails = false

    var body: some View {
        if count > 0 {
            Button {
                showingDetails = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(count)")
                        .font(.montserratSemiBold(size: 13))
                }
                .foregroundStyle(.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .stroke(.accent, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDetails) {
                prDetailsPopover
            }
        }
    }

    private var prDetailsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal Records")
                .font(.montserratSemiBold(size: 15))
                .padding(.bottom, 4)

            ForEach(details) { pr in
                HStack(spacing: 8) {
                    Text(pr.emoji)
                        .font(.system(size: 14))
                        .frame(width: 20)
                    Text(pr.name)
                        .font(.montserratRegular(size: 13))
                    if pr.isWeightPR {
                        Text("(weighted)")
                            .font(.montserratRegular(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .presentationCompactAdaptation(.popover)
    }
}

#Preview {
    PRTrophyBadge(
        count: 4,
        details: [
            PRDetail(emoji: "👟", name: "Most Steps", isWeightPR: false),
            PRDetail(emoji: "⏱️", name: "Longest Workout", isWeightPR: false),
            PRDetail(emoji: "🔥", name: "Most Calories Burned", isWeightPR: false),
            PRDetail(emoji: "👟", name: "Most Steps", isWeightPR: true)
        ]
    )
    .padding()
    .preferredColorScheme(.dark)
}
