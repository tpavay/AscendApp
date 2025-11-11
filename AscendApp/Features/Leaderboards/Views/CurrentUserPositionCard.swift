//
//  CurrentUserPositionCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct CurrentUserPositionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("\(entry.rank)")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.accent)
                .frame(width: 50)
            
            // Profile image
            if let photoURL = entry.photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    default:
                        defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }
            
            // Name and metric
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text(metric.displayName)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            
            Spacer()
            
            // Value
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.formattedValue)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.accent)
                
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 2)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accent.opacity(0.2))
                .frame(width: 50, height: 50)
            
            Image(systemName: "person.fill")
                .font(.system(size: 24))
                .foregroundStyle(.accent)
        }
    }
}

#Preview {
    CurrentUserPositionCard(
        entry: LeaderboardEntry(
            userId: "1",
            displayName: "You",
            rank: 44,
            value: 8500,
            formattedValue: "8,500",
            isCurrentUser: true
        ),
        metric: .steps
    )
    .themedBackground()
}
