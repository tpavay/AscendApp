//
//  ProfileHeaderView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct ProfileHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let userId: String?
    let photoURL: URL?
    let displayName: String
    let email: String?
    let onEditTap: (() -> Void)?
    
    init(
        userId: String?,
        photoURL: URL?,
        displayName: String,
        email: String? = nil,
        onEditTap: (() -> Void)? = nil
    ) {
        self.userId = userId
        self.photoURL = photoURL
        self.displayName = displayName
        self.email = email
        self.onEditTap = onEditTap
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Picture with Edit Button
            ZStack(alignment: .bottomTrailing) {
                ClimberAvatar(
                    userId: userId,
                    photoURL: photoURL,
                    placeholder: .glyph(
                        systemName: "person.fill",
                        fill: Color.jetLighter.opacity(0.3),
                        foreground: .white.opacity(0.7),
                        glyphSize: 50
                    ),
                    size: 120,
                    border: .init(color: .white.opacity(0.2), width: 2, onlyOverPhoto: true)
                )
                
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

#Preview {
    ProfileHeaderView(
        userId: nil,
        photoURL: nil,
        displayName: "Tyler Pavay"
    )
    .themedBackground()
}
