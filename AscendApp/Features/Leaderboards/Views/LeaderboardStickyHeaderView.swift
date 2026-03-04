//
//  LeaderboardStickyHeaderView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardStickyHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @Binding var selectedTimeFrame: LeaderboardTimeFrame
    let timeFrames: [LeaderboardTimeFrame]
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            topBar

            LeaderboardPickerView(
                selectedTimeFrame: $selectedTimeFrame,
                timeFrames: timeFrames
            )
            .padding(.horizontal, 20)
        }
        .safeAreaPadding(.top, 6)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(colorScheme == .dark ? Color.night : Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.08))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                HapticsManager.shared.trigger(.lightImpact)
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.8))
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.55))
                    )
                    .overlay(
                        Circle()
                            .stroke(colorScheme == .dark ? .white.opacity(0.15) : .black.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.montserratBold(size: 18))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 46, height: 46)
        }
        .padding(.horizontal, 20)
    }
}
