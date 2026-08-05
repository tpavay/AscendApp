//
//  ProfileHeaderView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct ProfileHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let photoURL: URL?
    let displayName: String
    let email: String?
    let onEditTap: (() -> Void)?
    
    init(
        photoURL: URL?,
        displayName: String,
        email: String? = nil,
        onEditTap: (() -> Void)? = nil
    ) {
        self.photoURL = photoURL
        self.displayName = displayName
        self.email = email
        self.onEditTap = onEditTap
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Picture with Edit Button
            ZStack(alignment: .bottomTrailing) {
                ProfileImageView(photoURL: photoURL)
                
                if let onEditTap = onEditTap {
                    Button(action: onEditTap) {
                        ZStack {
                            Circle()
                                .fill(Color.accent)
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
                    .accessibilityLabel("Edit profile")
                }
            }
            
            // Display Name
            Text(displayName.isEmpty ? "No Name Set" : displayName)
                .font(.montserratSemiBold)
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)

            if let email, !email.isEmpty {
                Text(email)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, -8)
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - Profile Image View

private struct ProfileImageView: View {
    let photoURL: URL?
    
    var body: some View {
        AsyncImage(url: photoURL) { phase in
            switch phase {
            case .empty:
                placeholderImage
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 2)
                    )
            case .failure:
                placeholderImage
            @unknown default:
                placeholderImage
            }
        }
        .frame(width: 120, height: 120)
    }
    
    private var placeholderImage: some View {
        ZStack {
            Circle()
                .fill(.jetLighter.opacity(0.3))
                .frame(width: 120, height: 120)
            
            Image(systemName: "person.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

#Preview {
    ProfileHeaderView(
        photoURL: nil,
        displayName: "Tyler Pavay"
    )
    .themedBackground()
}
