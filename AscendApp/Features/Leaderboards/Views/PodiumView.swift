//
//  PodiumView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct PodiumView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let topThree: [LeaderboardEntry]
    let metric: LeaderboardMetric
    
    var body: some View {
        VStack(spacing: 20) {
            // Podium visualization
            HStack(alignment: .bottom, spacing: 0) {
                // 2nd Place (Left)
                if topThree.count > 1 {
                    PodiumPosition(
                        entry: topThree[1],
                        metric: metric,
                        height: 140,
                        color: Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
                    )
                } else {
                    Spacer()
                }
                
                // 1st Place (Center, tallest)
                if !topThree.isEmpty {
                    PodiumPosition(
                        entry: topThree[0],
                        metric: metric,
                        height: 180,
                        color: .yellow
                    )
                }
                
                // 3rd Place (Right)
                if topThree.count > 2 {
                    PodiumPosition(
                        entry: topThree[2],
                        metric: metric,
                        height: 120,
                        color: Color(red: 0.8, green: 0.5, blue: 0.2) // Bronze
                    )
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct PodiumPosition: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    let height: CGFloat
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                Text("\(entry.rank)")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.black)
            }
            .offset(y: 16)
            .zIndex(2)
            
            // Profile picture with background
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(color.opacity(0.3))
                    .frame(height: height)
                
                VStack(spacing: 12) {
                    // Profile Image
                    if let photoURL = entry.photoURL {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(color, lineWidth: 3)
                                    )
                            default:
                                defaultAvatar
                            }
                        }
                    } else {
                        defaultAvatar
                    }
                    
                    // Name
                    Text(entry.displayName)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    // Value
                    Text(entry.formattedValue)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(color)
                    
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(.montserratRegular(size: 10))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 70, height: 70)
            
            Image(systemName: "person.fill")
                .font(.system(size: 30))
                .foregroundStyle(color)
        }
        .overlay(
            Circle()
                .stroke(color, lineWidth: 3)
        )
    }
}

#Preview {
    PodiumView(
        topThree: [
            LeaderboardEntry(userId: "1", displayName: "John Doe", rank: 1, value: 15000, formattedValue: "15,000"),
            LeaderboardEntry(userId: "2", displayName: "Jane Smith", rank: 2, value: 12000, formattedValue: "12,000"),
            LeaderboardEntry(userId: "3", displayName: "Bob Wilson", rank: 3, value: 10000, formattedValue: "10,000")
        ],
        metric: .steps
    )
    .padding()
    .themedBackground()
}
