//
//  WorkoutRowView.swift
//  AscendApp
//
//  Extracted from WorkoutListView.swift for maintainability.
//

import SwiftUI

struct WorkoutRowView: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var formattedDateTime: String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        if calendar.isDateInToday(workout.date) {
            return "Today at \(timeFormatter.string(from: workout.date))"
        } else if calendar.isDateInYesterday(workout.date) {
            return "Yesterday at \(timeFormatter.string(from: workout.date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
        }
    }

    private var paceText: String? {
        guard let pace = workout.pace(for: preferredMetric) else { return nil }
        let unit = preferredMetric == .steps ? "spm" : "fpm"
        return "\(Int(pace)) \(unit)"
    }

    /// Formats metric value compactly for large numbers (100K+)
    private var compactMetricValue: String {
        let value = workout.metricValue(for: preferredMetric)
        if value >= 100_000 {
            let rounded = (Double(value) / 100).rounded() * 100
            let inK = rounded / 1000
            if inK.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(inK))K"
            } else {
                return "\(inK.formatted(.number.precision(.fractionLength(1))))K"
            }
        } else {
            return value.formatted()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Title (left) + Date/Time/Strava (right)
            HStack(alignment: .top, spacing: 8) {
                Text(workout.name)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack(spacing: 6) {
                    Text(formattedDateTime)
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                    if FeatureFlags.isStravaEnabled && workout.isSyncedToStrava {
                        Image("strava-icon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Color(red: 252/255, green: 76/255, blue: 2/255))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            // Separator line
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)

            // Main stats row
            HStack(spacing: 6) {
                Text("\(compactMetricValue) \(preferredMetric.unit)")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text("\u{2022}")
                    .font(.system(size: 10))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.6))

                Text(workout.durationFormatted)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                if let pace = paceText {
                    Text("\u{2022}")
                        .font(.system(size: 10))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.6))
                    Text(pace)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }

                Spacer()

                if workout.hasWeights {
                    WeightIndicatorBadge(size: .small)
                }

                if workout.hasPersonalRecords {
                    let prCount = workout.achievedPersonalRecords.count
                    Text("\u{1F3C6} \(prCount)")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(.accent)
                        )
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            if !workout.notes.isEmpty {
                Text(workout.notes)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !workout.photos.isEmpty {
                WorkoutCardMediaSection(workout: workout)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1.5)
                )
        )
    }
}
