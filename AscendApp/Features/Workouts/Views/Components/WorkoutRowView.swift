//
//  WorkoutRowView.swift
//  AscendApp
//
//  Extracted from WorkoutListView.swift for maintainability.
//

import SwiftUI

struct WorkoutRowView: View {
    let workout: Workout
    var bestEffort: RankedBestEffort? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
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

    private var compactStepsValue: String {
        let value = workout.steps
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
            // Header: Title (left) + Date/time (right)
            HStack(alignment: .top, spacing: 8) {
                Text(workout.name)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Text(formattedDateTime)
                    .font(.montserratRegular(size: 11))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // Separator line
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)

            // Main stats row
            HStack(spacing: 6) {
                Text("\(compactStepsValue) steps")
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

                Spacer()

                if workout.hasWeights {
                    WeightIndicatorBadge(size: .small)
                }

            }

            if let bestEffort {
                WorkoutRowBestEffortBadge(
                    effort: bestEffort,
                    colorScheme: effectiveColorScheme
                )
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
        .overlay(alignment: .leading) {
            if let bestEffort {
                LeadingAccentStripe(
                    color: bestEffort.trophyColor,
                    width: 3,
                    cornerRadius: 12
                )
                .opacity(0.92)
            }
        }
    }
}

private struct WorkoutRowBestEffortBadge: View {
    let effort: RankedBestEffort
    let colorScheme: ColorScheme

    private var accentColor: Color {
        effort.trophyColor
    }

    var body: some View {
        HStack(spacing: 6) {
            WorkoutRowBestEffortIcon(effort: effort)

            Text(effort.sentence)
                .font(.montserratMedium(size: 10.5))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.top, -3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Best Effort, \(effort.sentence)")
    }

    private var textColor: Color {
        accentColor.opacity(colorScheme == .dark ? 0.88 : 0.78)
    }
}

private struct WorkoutRowBestEffortIcon: View {
    let effort: RankedBestEffort

    private var accentColor: Color {
        effort.trophyColor
    }

    var body: some View {
        Group {
            if effort.rank == 1 {
                Image("best-effort-laurel-wreath")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 12)
                    .shadow(color: accentColor.opacity(0.28), radius: 3, x: 0, y: 0)
            } else {
                ZStack(alignment: .top) {
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(accentColor.opacity(0.4))
                            .frame(width: 4, height: 6)
                            .rotationEffect(.degrees(14))

                        RoundedRectangle(cornerRadius: 1)
                            .fill(accentColor.opacity(0.28))
                            .frame(width: 4, height: 6)
                            .rotationEffect(.degrees(-14))
                    }
                    .offset(y: 9)

                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 14, height: 14)

                    Circle()
                        .stroke(accentColor.opacity(0.85), lineWidth: 1)
                        .frame(width: 14, height: 14)

                    Text("\(effort.rank)")
                        .font(.montserratBold(size: 8.5))
                        .foregroundStyle(accentColor)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 16, height: 16)
            }
        }
        .frame(width: 18, height: 16)
    }
}
