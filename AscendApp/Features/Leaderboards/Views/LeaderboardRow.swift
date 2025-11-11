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
            return .yellow
        case 2:
            return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case 3:
            return Color(red: 0.8, green: 0.5, blue: 0.2) // Bronze
        default:
            return colorScheme == .dark ? .white.opacity(0.6) : .gray
        }
    }
    
    private var rankIcon: String? {
        switch entry.rank {
        case 1:
            return "trophy.fill"
        case 2:
            return "medal.fill"
        case 3:
            return "medal.fill"
        default:
            return nil
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            ZStack {
                if let icon = rankIcon {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(rankColor)
                } else {
                    Text("\(entry.rank)")
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(rankColor)
                }
            }
            .frame(width: 40)
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                
                Text(metric.displayName)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
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
                .fill(entry.isCurrentUser 
                    ? Color.accent.opacity(0.1)
                    : (colorScheme == .dark ? Color("Jet") : Color.white)
                )
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
