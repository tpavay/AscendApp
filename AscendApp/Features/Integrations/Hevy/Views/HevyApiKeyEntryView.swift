//
//  HevyApiKeyEntryView.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import SwiftUI

struct HevyApiKeyEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var hevyManager = HevyManager.shared

    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var onSuccess: () -> Void

    // Hevy brand color
    private let hevyColor = Color(red: 45/255, green: 51/255, blue: 107/255)

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image("hevy-icon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(.rect(cornerRadius: 16))

                        Text("Connect to Hevy")
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        Text("Import your Stair Machine workouts from Hevy")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Requirements
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Requirements")
                            .font(.montserratSemiBold(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 14))
                            Text("Hevy Pro subscription")
                                .font(.montserratRegular(size: 14))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "figure.stair.stepper")
                                .foregroundStyle(hevyColor)
                                .font(.system(size: 14))
                            Text("At least one Stair Machine exercise logged in Hevy")
                                .font(.montserratRegular(size: 14))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.05))
                    )

                    // Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to get your API key")
                            .font(.montserratSemiBold(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        instructionRow(number: 1, text: "Open hevy.com in a browser")
                        instructionRow(number: 2, text: "Sign in to your account")
                        instructionRow(number: 3, text: "Go to Settings → Developer")
                        instructionRow(number: 4, text: "Copy your API key")

                        Link(destination: URL(string: "https://hevy.com/settings?developer")!) {
                            HStack {
                                Text("Open Hevy Developer Settings")
                                    .font(.montserratMedium(size: 14))
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(hevyColor)
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // API Key input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        SecureField("Paste your API key here", text: $apiKey)
                            .font(.montserratRegular(size: 16))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        errorMessage != nil ? .red.opacity(0.5) : .clear,
                                        lineWidth: 1
                                    )
                            )
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Connect button
                    Button(action: connect) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(isConnecting ? "Connecting..." : "Connect")
                                .font(.montserratSemiBold(size: 16))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(apiKey.isEmpty || isConnecting ? hevyColor.opacity(0.5) : hevyColor)
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(apiKey.isEmpty || isConnecting)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .preferredColorScheme(effectiveColorScheme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
            }
        }
    }

    @ViewBuilder
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.montserratBold(size: 12))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hevyColor))

            Text(text)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
        }
    }

    /// Sanitizes API key input to prevent injection attacks
    private func sanitizeApiKey(_ input: String) -> String? {
        // Trim whitespace and newlines
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject empty input
        guard !trimmed.isEmpty else { return nil }

        // Remove any control characters (prevents header injection)
        let sanitized = trimmed.unicodeScalars.filter { scalar in
            // Allow only printable ASCII characters (0x20-0x7E)
            scalar.value >= 0x20 && scalar.value <= 0x7E
        }

        let result = String(String.UnicodeScalarView(sanitized))

        // Ensure something remains after sanitization
        guard !result.isEmpty else { return nil }

        return result
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                guard let sanitizedKey = sanitizeApiKey(apiKey) else {
                    errorMessage = "Please enter a valid API key"
                    isConnecting = false
                    return
                }

                try await hevyManager.connect(apiKey: sanitizedKey)
                onSuccess()
            } catch let error as HevyError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Connection failed: \(error.localizedDescription)"
            }
            isConnecting = false
        }
    }
}

#Preview("Light") {
    HevyApiKeyEntryView(onSuccess: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HevyApiKeyEntryView(onSuccess: {})
        .preferredColorScheme(.dark)
}
