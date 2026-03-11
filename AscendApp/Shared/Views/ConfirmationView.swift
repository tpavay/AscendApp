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
    let isLoading: Bool
    let isCancelling: Bool
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
        isLoading: Bool = false,
        isCancelling: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.cancelButtonText = cancelButtonText
        self.confirmButtonText = confirmButtonText
        self.isDestructive = isDestructive
        self.isLoading = isLoading
        self.isCancelling = isCancelling
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        AppSheetScaffold(title: title, message: message) {
            EmptyView()
        } footer: {
            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    if isCancelling {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(effectiveColorScheme == .dark ? .white : .black)
                                .scaleEffect(0.8)
                            Text("Stopping...")
                        }
                    } else {
                        Text(cancelButtonText)
                    }
                }
                .appSheetButtonStyle(tone: .secondary)
                .disabled(isCancelling)
                .opacity(isLoading && !isCancelling ? 0.7 : 1)

                Button {
                    onConfirm()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(confirmButtonText)
                    }
                }
                .appSheetButtonStyle(tone: isDestructive ? .destructive : .primary)
                .disabled(isLoading || isCancelling)
            }
        }
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
