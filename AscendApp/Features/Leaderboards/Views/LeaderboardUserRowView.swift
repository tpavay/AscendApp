//
//  LeaderboardUserRowView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardUserRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric

    private var rowFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var shouldShowYouBadge: Bool {
        entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("you") != .orderedSame
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.montserratBold(size: 30))
                .foregroundStyle(.accent)
                .frame(width: 38, alignment: .leading)

            profileImage
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                if shouldShowYouBadge {
                    Text("YOU")
                        .font(.montserratBold(size: 9))
                        .foregroundStyle(.accent)
                        .lineLimit(1)
                }

                Text(entry.displayName.uppercased())
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 8)

            Text(entry.formattedValue)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(primaryTextColor.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accent)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your rank \(entry.rank), \(entry.displayName), \(entry.formattedValue) \(metric.displayName)")
    }

    @ViewBuilder
    private var profileImage: some View {
        if let photoURL = entry.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(.circle)
                case .failure:
                    defaultAvatar
                case .empty:
                    defaultAvatar
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                        )
                @unknown default:
                    defaultAvatar
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.accent.opacity(0.78), lineWidth: 1.5)
            )
            .id(photoURL)
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color.accent.opacity(colorScheme == .dark ? 0.22 : 0.16))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.accent)
            )
            .overlay(
                Circle()
                    .stroke(Color.accent.opacity(0.78), lineWidth: 1.5)
            )
    }
}

#Preview {
    LeaderboardUserRowView(
        entry: LeaderboardEntry(
            userId: "1",
            displayName: "Ryan T.",
            rank: 4,
            value: 15_872_211,
            formattedValue: "15,872,211",
            isCurrentUser: true
        ),
        metric: .climb
    )
    .background(Color.black)
}
