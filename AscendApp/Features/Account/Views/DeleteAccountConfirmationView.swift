//
//  DeleteAccountConfirmationView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/25/25.
//

import SwiftUI

struct DeleteAccountConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @FocusState private var isTextFieldFocused: Bool

    let onAccountDeleted: () -> Void

    private let deletionService = AccountDeletionService()
    private let requiredConfirmation = "DELETE"

    private var canDelete: Bool {
        confirmationText.uppercased() == requiredConfirmation
    }

    var body: some View {
        VStack(spacing: 24) {
            // Title and message
            VStack(spacing: 12) {
                Text("Delete Account")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Confirmation input
            if isDeleting {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type DELETE to confirm")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)

                    TextField("", text: $confirmationText)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    canDelete ? Color.red : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                                    lineWidth: canDelete ? 2 : 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.2), value: canDelete)
                }
            }

            // Buttons
            if !isDeleting {
                VStack(spacing: 12) {
                    Button(action: deleteAccount) {
                        Text("Delete Account")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(canDelete ? Color.red : Color.gray.opacity(0.4))
                            )
                    }
                    .disabled(!canDelete)
                    .animation(.easeInOut(duration: 0.2), value: canDelete)

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDeleting)
        .alert("Deletion Failed", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Actions

    private func deleteAccount() {
        HapticsManager.shared.trigger(.warning)
        isTextFieldFocused = false
        isDeleting = true

        Task {
            do {
                try await deletionService.deleteAccount(modelContext: modelContext)

                await MainActor.run {
                    onAccountDeleted()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            DeleteAccountConfirmationView(onAccountDeleted: {})
        }
}
