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
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Picture
            ProfileImageView(photoURL: photoURL)
            
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
