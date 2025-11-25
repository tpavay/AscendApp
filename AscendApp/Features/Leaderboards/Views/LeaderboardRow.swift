//
//  LeaderboardRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    
    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }
    
    private var rankPalette: (text: Color, badge: Color) {
        let isDark = colorScheme == .dark
        switch entry.rank {
        case 1:
            return (
                text: isDark
                    ? Color(red: 1.0, green: 0.92, blue: 0.55)
                    : Color(red: 0.76, green: 0.58, blue: 0.0),
                badge: isDark
                    ? Color(red: 0.45, green: 0.37, blue: 0.08)
                    : Color(red: 1.0, green: 0.93, blue: 0.63)
            )
        case 2:
            return (
                text: isDark
                    ? Color(red: 0.78, green: 0.81, blue: 0.96)
                    : Color(red: 0.44, green: 0.47, blue: 0.6),
                badge: isDark
                    ? Color(red: 0.32, green: 0.32, blue: 0.46)
                    : Color(red: 0.9, green: 0.9, blue: 0.95)
            )
        case 3:
            return (
                text: isDark
                    ? Color(red: 0.98, green: 0.79, blue: 0.61)
                    : Color(red: 0.71, green: 0.41, blue: 0.19),
                badge: isDark
                    ? Color(red: 0.42, green: 0.28, blue: 0.16)
                    : Color(red: 0.96, green: 0.87, blue: 0.78)
            )
        default:
            return (
                text: isDark ? .white.opacity(0.6) : .gray,
                badge: isDark ? Color("Jet").opacity(0.8) : Color.gray.opacity(0.15)
            )
        }
    }
    
    private var rankColor: Color { rankPalette.text }
    
    private var highlightedBackground: Color {
        switch entry.rank {
        case 1:
            return colorScheme == .dark
                ? Color(red: 0.42, green: 0.35, blue: 0.12)
                : Color(red: 1.0, green: 0.97, blue: 0.85)
        case 2:
            return colorScheme == .dark
                ? Color(red: 0.35, green: 0.35, blue: 0.49)
                : Color(red: 0.95, green: 0.95, blue: 0.97)
        case 3:
            return colorScheme == .dark
                ? Color(red: 0.43, green: 0.28, blue: 0.17)
                : Color(red: 0.98, green: 0.93, blue: 0.88)
        default:
            return colorScheme == .dark
                ? Color(red: 0.18, green: 0.18, blue: 0.18)
                : Color.white
        }
    }

    private var rowBackground: Color {
        if entry.isCurrentUser {
            return Color.accent.opacity(0.1)
        }
        return highlightedBackground
    }
    
    private var rowBorderColor: Color {
        if entry.isCurrentUser {
            return Color.accent.opacity(0.3)
        }
        if colorScheme == .light && entry.rank > 3 {
            return Color.gray.opacity(0.15)
        }
        return .clear
    }

    private var rankBadgeBackground: Color { rankPalette.badge }

    private var rankBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(rankBadgeBackground)
                .frame(width: 60, height: 60)

            VStack(spacing: 4) {
                if entry.rank <= 3 {
                    Image(systemName: entry.rank == 1 ? "trophy.fill" : "medal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(rankColor)
                }
                Text("#\(entry.rank)")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(rankColor)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            rankBadge
            
            // User info
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.displayName)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Value
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.formattedValue)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                
                let unitLabel = metric.unit(for: preferredMetric)
                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(rowBorderColor, lineWidth: 2)
        )
        .padding(.horizontal, 20)
    }
}

#Preview {
    VStack(spacing: 12) {
        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: "1",
                displayName: "John Doe",
                rank: 1,
                value: 15000,
                formattedValue: "15,000",
                isCurrentUser: false
            ),
            metric: .climb
        )
        
        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: "2",
                displayName: "You",
                rank: 5,
                value: 12000,
                formattedValue: "12,000",
                isCurrentUser: true
            ),
            metric: .climb
        )
    }
    .themedBackground()
}
