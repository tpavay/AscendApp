//
//  WeekStartSelectionView.swift
//  AscendApp
//

import SwiftData
import SwiftUI

struct WeekStartSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 20)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Pick how your week is grouped across goals and leaderboard.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.75) : .gray)

                    VStack(spacing: 12) {
                        ForEach(WeekStartDay.allCases) { day in
                            optionRow(day: day)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)

                Spacer(minLength: 40)
            }
        }
        .themedBackground()
        .navigationTitle("Week Starts On")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    private func optionRow(day: WeekStartDay) -> some View {
        Button {
            guard settingsManager.weekStartDay != day else { return }
            HapticsManager.shared.trigger(.selection)
            settingsManager.setWeekStartDay(day)
            syncActiveGoalIfNeeded(with: day)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 46, height: 46)

                    Image(systemName: day == .monday ? "calendar.badge.clock" : "calendar")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(day.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    Text(day == .monday ? "Most fitness plans use Monday starts" : "Matches many U.S. calendars")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.65) : .gray)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if settingsManager.weekStartDay == day {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                            .scaleEffect(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.15) : .gray.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settingsManager.weekStartDay == day ? .accent.opacity(0.5) :
                                    (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)),
                                    lineWidth: settingsManager.weekStartDay == day ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func syncActiveGoalIfNeeded(with day: WeekStartDay) {
        let goalService = GoalService(modelContext: modelContext)
        do {
            try goalService.updateActiveGoalWeekRules(
                firstWeekday: day.firstWeekday,
                timeZoneId: TimeZone.current.identifier
            )
            NotificationCenter.default.post(name: .weeklyGoalDidChange, object: nil)
        } catch {
            // Keep preference update even if goal rule sync fails.
        }
    }
}

#Preview {
    NavigationStack {
        WeekStartSelectionView()
    }
}
