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
    @State private var deletionProgress: AccountDeletionService.DeletionProgress?
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
        ZStack {
            // Background
            backgroundGradient
            
            // Content
            ScrollView {
                VStack(spacing: 0) {
                    // Close button
                    if !isDeleting {
                        closeButton
                    }
                    
                    Spacer()
                        .frame(height: 40)
                    
                    // Warning Icon with animation
                    warningHeader
                        .padding(.bottom, 32)
                    
                    // What will be deleted
                    deletionInfoSection
                        .padding(.bottom, 32)
                    
                    // Confirmation input or Progress
                    if isDeleting {
                        progressSection
                    } else {
                        confirmationSection
                            .padding(.bottom, 24)
                        
                        actionButtons
                    }
                    
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 24)
            }
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
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.12, green: 0.08, blue: 0.08), Color(red: 0.08, green: 0.06, blue: 0.06)]
                : [Color(red: 1.0, green: 0.97, blue: 0.97), .white],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Close Button
    
    private var closeButton: some View {
        HStack {
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                    )
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Warning Header
    
    private var warningHeader: some View {
        VStack(spacing: 20) {
            // Animated warning icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red.opacity(0.3), Color.red.opacity(0)],
                            center: .center,
                            startRadius: 40,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.25), Color.red.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                // Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, Color(red: 0.8, green: 0.2, blue: 0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("Delete Account")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text("This action is permanent and cannot be undone")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Deletion Info Section
    
    private var deletionInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What will be deleted")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                .textCase(.uppercase)
                .tracking(1)
            
            VStack(spacing: 0) {
                deletionItem(icon: "person.fill", text: "Profile & account data", isFirst: true)
                deletionItem(icon: "figure.stair.stepper", text: "All workouts & statistics")
                deletionItem(icon: "photo.stack.fill", text: "Photos & videos")
                deletionItem(icon: "trophy.fill", text: "Personal records")
                deletionItem(icon: "chart.line.uptrend.xyaxis", text: "Leaderboard rankings")
                deletionItem(icon: "icloud.fill", text: "Cloud-synced data", isLast: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    private func deletionItem(icon: String, text: String, isFirst: Bool = false, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }
                
                Text(text)
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.75))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if !isLast {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .frame(height: 1)
                    .padding(.leading, 66)
            }
        }
    }
    
    // MARK: - Confirmation Section
    
    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type \(requiredConfirmation) to confirm")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
            
            TextField("", text: $confirmationText)
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            canDelete ? Color.red : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                            lineWidth: canDelete ? 2 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: canDelete)
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 24) {
            // Custom progress indicator
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: deletionProgress?.progressPercentage ?? 0)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: deletionProgress?.progressPercentage)
                
                Text("\(Int((deletionProgress?.progressPercentage ?? 0) * 100))%")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
            }
            
            VStack(spacing: 8) {
                if let progress = deletionProgress {
                    Text(progress.currentStep)
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
                
                Text("Please don't close the app")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
            }
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Delete button
            Button(action: deleteAccount) {
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete My Account")
                        .font(.montserratSemiBold(size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            canDelete
                                ? LinearGradient(colors: [.red, Color(red: 0.75, green: 0.15, blue: 0.15)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                        )
                )
                .shadow(color: canDelete ? .red.opacity(0.3) : .clear, radius: 12, y: 4)
            }
            .disabled(!canDelete)
            .animation(.easeInOut(duration: 0.2), value: canDelete)
            
            // Cancel button
            Button(action: { dismiss() }) {
                Text("Keep My Account")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
        }
    }
    
    // MARK: - Actions
    
    private func deleteAccount() {
        isTextFieldFocused = false
        isDeleting = true
        
        Task {
            do {
                try await deletionService.deleteAccount(
                    modelContext: modelContext,
                    progressHandler: { progress in
                        deletionProgress = progress
                    }
                )
                
                // Success - notify parent and dismiss
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
    DeleteAccountConfirmationView(onAccountDeleted: {})
}
