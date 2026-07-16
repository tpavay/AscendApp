//
//  CelebrationLeaderboardRow.swift
//  AscendApp
//

import SwiftUI

struct CelebrationLeaderboardRow: View {
    let entry: CelebrationLeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(entry.isCurrentUser ? .accent : .secondary)
                .frame(width: 36, alignment: .leading)

            avatar

            Text(entry.displayName)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(entry.formattedValue)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(entry.isCurrentUser ? .accent : .white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(entry.isCurrentUser ? .accent.opacity(0.16) : .white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(entry.isCurrentUser ? .accent.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURLString = entry.photoURL,
           let url = URL(string: photoURLString),
           !photoURLString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholderAvatar
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(.circle)
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(.white.opacity(0.14))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            )
    }
}
