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
    let onEditTap: (() -> Void)?
    
    init(photoURL: URL?, displayName: String, onEditTap: (() -> Void)? = nil) {
        self.photoURL = photoURL
        self.displayName = displayName
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
                }
            }
            
            // Display Name
            Text(displayName.isEmpty ? "No Name Set" : displayName)
                .font(.montserratSemiBold)
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
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
