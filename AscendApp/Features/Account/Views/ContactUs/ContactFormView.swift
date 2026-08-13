//
//  ContactFormView.swift
//  AscendApp
//
//  Created by Claude on 1/4/26.
//

import SwiftUI

struct ContactFormView: View {
    let feedbackType: FeedbackType

    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var errorMessage: String?

    @FocusState private var isMessageFocused: Bool

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var isFormValid: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    private var cooldownRemaining: Int? {
        FeedbackService.shared.getCooldownRemaining()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header info card
                headerInfoCard

                // Message input
                messageInput

                // Character count hint
                characterCountHint

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .themedBackground()
        .preferredColorScheme(effectiveColorScheme)
        .navigationTitle(feedbackType.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sendButton
            }
        }
        .keyboardDoneToolbar()
        .alert("Feedback Sent!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for your feedback. We'll review it soon!")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onAppear {
            isMessageFocused = true
        }
        .trackOnce(screen: .contactForm)
    }

    // MARK: - Subviews

    private var headerInfoCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(feedbackType.iconColor.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: feedbackType.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(feedbackType.iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(feedbackType.displayName)
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("We read every message")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var messageInput: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $message)
                .focused($isMessageFocused)
                .font(.montserratRegular(size: 16))
                .frame(minHeight: 200, maxHeight: 300)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            if message.isEmpty {
                Text(feedbackType.placeholderText)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.gray.opacity(0.6))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
        )
    }

    private var characterCountHint: some View {
        HStack {
            let charCount = message.trimmingCharacters(in: .whitespacesAndNewlines).count

            if let remaining = cooldownRemaining {
                Text("Please wait \(remaining) seconds")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.orange)
            } else if charCount < 10 {
                Text("Minimum 10 characters (\(charCount)/10)")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.orange)
            } else {
                Text("\(charCount) characters")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: submitFeedback) {
            if isSubmitting {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(effectiveColorScheme == .dark ? .white : .accent)
            } else {
                Text("Send")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(isFormValid && cooldownRemaining == nil ? .accent : .gray)
            }
        }
        .disabled(!isFormValid || isSubmitting || cooldownRemaining != nil)
    }

    // MARK: - Actions

    private func submitFeedback() {
        isSubmitting = true

        Task {
            do {
                try await FeedbackService.shared.submitFeedback(
                    type: feedbackType,
                    message: message,
                    userId: authVM.user?.uid ?? "anonymous",
                    userEmail: authVM.user?.email
                )

                HapticsManager.shared.trigger(.success)
                showSuccessAlert = true
            } catch {
                HapticsManager.shared.trigger(.error)
                errorMessage = error.localizedDescription
            }

            isSubmitting = false
        }
    }
}

#Preview("Dark Theme") {
    NavigationStack {
        ContactFormView(feedbackType: .bugReport)
            .environment(AuthenticationViewModel())
    }
    .preferredColorScheme(.dark)
}
