//
//  ConfirmationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/21/25.
//


import SwiftUI

struct ConfirmationView: View {
    let title: String
    let message: String?
    let cancelButtonText: String
    let confirmButtonText: String
    let isDestructive: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(
        title: String,
        message: String? = nil,
        cancelButtonText: String = "Cancel",
        confirmButtonText: String = "Confirm",
        isDestructive: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.cancelButtonText = cancelButtonText
        self.confirmButtonText = confirmButtonText
        self.isDestructive = isDestructive
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header section
            VStack(spacing: 8) {
                Text(title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ?
                        .white : .black)

                if let message = message {
                    Text(message)
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ?
                            .white.opacity(0.8) : .gray)
                        .multilineTextAlignment(.center)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                // Cancel button
                Button(cancelButtonText) {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(effectiveColorScheme == .dark ?
                            .white.opacity(0.1) : .gray.opacity(0.1))
                )
                .foregroundStyle(effectiveColorScheme == .dark ? .white :
                        .black)

                // Confirm button
                Button(confirmButtonText) {
                    onConfirm()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDestructive ? .red : .accent)
                )
                .foregroundStyle(.white)
            }
        }
        .padding(20)
        .themedBackground()
    }
}

#Preview("Destructive") {
    ConfirmationView(
        title: "Delete Item",
        message: "Are you sure you want to delete this item? This action cannot be undone.",
        confirmButtonText: "Delete",
        isDestructive: true,
        onCancel: { print("Cancelled") },
        onConfirm: { print("Confirmed") }
    )
}

#Preview("Non-destructive") {
    ConfirmationView(
        title: "Save Changes",
        message: "Do you want to save your changes?",
        confirmButtonText: "Save",
        isDestructive: false,
        onCancel: { print("Cancelled") },
        onConfirm: { print("Saved") }
    )
}

#Preview("No Message") {
    ConfirmationView(
        title: "Confirm Action",
        confirmButtonText: "Continue",
        isDestructive: false,
        onCancel: { print("Cancelled") },
        onConfirm: { print("Confirmed") }
    )
}
