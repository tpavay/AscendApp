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
    @State private var progressMessage = "Starting deletion..."
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var deletionTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var didTimeout = false
    @FocusState private var isTextFieldFocused: Bool

    let onAccountDeleted: () -> Void

    private let deletionService = AccountDeletionService()
    private let requiredConfirmation = "DELETE"
    private let deletionTimeout: Duration = .seconds(90)

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

                // Apple's "Offering account deletion in your app" asks by name that a subscriber be
                // told billing continues through Apple and be asked to cancel first. Deleting the
                // Ascend account cannot touch an App Store subscription, so silence here would be a
                // surprise charge.
                Text("This will permanently delete your account and all associated data. This action cannot be undone. If you have an Ascend subscription, it’s billed by Apple and keeps renewing after deletion, so cancel it in your Apple subscription settings before you continue. For security, you may be asked to sign in again before deletion is completed.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Confirmation input
            if isDeleting {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding(.top, 8)

                    Text(progressMessage)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Text("If prompted, confirm your sign-in to finish account deletion.")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.55) : .gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 12)
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
        .appSheetBackground()
        .appSheetStyle(.fittedScrolling(), isInteractiveDismissDisabled: isDeleting)
        .onDisappear {
            cancelInFlightTasks()
        }
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
        showError = false
        errorMessage = nil
        isDeleting = true
        didTimeout = false
        progressMessage = "Starting deletion..."

        cancelInFlightTasks()

        deletionTask = Task {
            do {
                try await deletionService.deleteAccount(
                    modelContext: modelContext,
                    progressHandler: { progress in
                        Task { @MainActor in
                            progressMessage = progress.currentStep
                        }
                    }
                )

                await MainActor.run {
                    cancelInFlightTasks()
                    isDeleting = false
                    onAccountDeleted()
                    dismiss()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard isDeleting, !didTimeout else { return }
                    finishDeletionWithError("Account deletion was cancelled. Please try again.")
                }
            } catch {
                await MainActor.run {
                    finishDeletionWithError(errorMessage(for: error))
                }
            }
        }

        timeoutTask = Task {
            try? await Task.sleep(for: deletionTimeout)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard isDeleting else { return }
                didTimeout = true
                deletionTask?.cancel()
                finishDeletionWithError("Account deletion timed out. Please check your internet connection and try again.")
            }
        }
    }

    private func finishDeletionWithError(_ message: String) {
        cancelInFlightTasks()
        isDeleting = false
        errorMessage = message
        showError = true
    }

    private func cancelInFlightTasks() {
        deletionTask?.cancel()
        timeoutTask?.cancel()
        deletionTask = nil
        timeoutTask = nil
    }

    private func errorMessage(for error: Error) -> String {
        if let deletionError = error as? AccountDeletionService.DeletionError {
            return deletionError.localizedDescription
        }
        return error.userFriendlyMessage
    }
}

#Preview {
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            DeleteAccountConfirmationView(onAccountDeleted: {})
        }
}
