//
//  DeletePhotoConfirmationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/13/25.
//

import SwiftUI

struct DeletePhotoConfirmationView: View {
    let onDelete: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 16) {
                Text("Delete Photo?")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.montserratSemiBold)
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )
                    }

                    Button(action: onDelete) {
                        Text("Delete")
                            .font(.montserratSemiBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.red)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .themedBackground()
    }
}

#Preview {
    DeletePhotoConfirmationView(
        onDelete: { print("Delete photo tapped") },
        onCancel: { print("Cancel tapped") }
    )
}
