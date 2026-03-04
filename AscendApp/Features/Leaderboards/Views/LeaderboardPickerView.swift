//
//  LeaderboardPickerView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardPickerView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedTimeFrame: LeaderboardTimeFrame
    let timeFrames: [LeaderboardTimeFrame]

    private var pickerContainerFill: Color {
        colorScheme == .dark ? Color.jet.opacity(0.9) : Color.white.opacity(0.95)
    }

    private var pickerContainerStroke: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.1)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(timeFrames) { timeFrame in
                let isSelected = selectedTimeFrame == timeFrame
                Button {
                    guard selectedTimeFrame != timeFrame else { return }
                    HapticsManager.shared.trigger(.selection)
                    selectedTimeFrame = timeFrame
                } label: {
                    Text(timeFrame.displayName)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(
                            isSelected
                                ? .accent
                                : (colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.72))
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                        : .clear
                                )
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    isSelected
                                        ? Color.accent.opacity(0.95)
                                        : .clear,
                                    lineWidth: 1.5
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(pickerContainerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(pickerContainerStroke, lineWidth: 1)
        )
    }
}

#Preview {
    LeaderboardPickerView(
        selectedTimeFrame: .constant(.weekly),
        timeFrames: [.weekly, .monthly, .allTime]
    )
    .padding()
    .themedBackground()
}
