//
//  LeaderboardRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    
    private var rankColor: Color {
        switch entry.rank {
        case 1:
            return Color(red: 0.99, green: 0.84, blue: 0.33)
        case 2:
            return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case 3:
            return Color(red: 0.8, green: 0.5, blue: 0.2) // Bronze
        default:
            return colorScheme == .dark ? .white.opacity(0.6) : .gray
        }
    }
    
    private var highlightedBackground: Color {
        switch entry.rank {
        case 1:
            return Color(red: 1.0, green: 0.97, blue: 0.85)
        case 2:
            return Color(red: 0.95, green: 0.95, blue: 0.97)
        case 3:
            return Color(red: 0.98, green: 0.93, blue: 0.88)
        default:
            return colorScheme == .dark ? Color("Jet") : Color.white
        }
    }

    private var rowBackground: Color {
        if entry.isCurrentUser {
            return Color.accent.opacity(0.1)
        }
        return highlightedBackground
    }

    private var rankBadgeBackground: Color {
        switch entry.rank {
        case 1:
            return Color(red: 0.99, green: 0.93, blue: 0.65)
        case 2:
            return Color(red: 0.88, green: 0.88, blue: 0.92)
        case 3:
            return Color(red: 0.95, green: 0.84, blue: 0.73)
        default:
            return colorScheme == .dark ? Color("Jet").opacity(0.8) : Color.gray.opacity(0.15)
        }
    }

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
                
                if !metric.unit.isEmpty {
                    Text(metric.unit)
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
                .stroke(entry.isCurrentUser ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 2)
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
            metric: .steps
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
            metric: .steps
        )
    }
    .themedBackground()
}
