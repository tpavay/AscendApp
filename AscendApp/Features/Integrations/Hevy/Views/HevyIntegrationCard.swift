//
//  HevyIntegrationCard.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import SwiftUI

struct HevyIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var hevyManager = HevyManager.shared
    @State private var hevyImportService = HevyImportService.shared
    @State private var showingApiKeyEntry = false
    @State private var showingDisconnectConfirmation = false
    @State private var importedCount: Int?

    // Hevy brand color (dark purple/blue)
    private let hevyColor = Color(red: 45/255, green: 51/255, blue: 107/255)

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Main row: Icon | Hevy | Connect/Disconnect
            HStack(spacing: 12) {
                // Hevy icon
                Image("hevy-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .cornerRadius(8)

                Text("Hevy")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                // Connect/Disconnect button
                if hevyManager.isConnecting || hevyImportService.isImporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if hevyManager.isConnected {
                    Button("Disconnect") {
                        showingDisconnectConfirmation = true
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.red)
                } else {
                    Button("Connect") {
                        showingApiKeyEntry = true
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(hevyColor)
                }
            }

            // Description (when not connected)
            if !hevyManager.isConnected && !hevyManager.isConnecting {
                Text("Import your Stair Machine workouts from Hevy. Requires Hevy Pro subscription.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Error message
            if let error = hevyManager.connectionError {
                Text(error.localizedDescription)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = hevyImportService.lastError {
                Text(error.localizedDescription)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Import section (when connected and no errors)
            if hevyManager.isConnected && hevyImportService.lastError == nil {
                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                // Import status
                if let count = importedCount {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Imported \(count) workout\(count == 1 ? "" : "s")")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if hevyImportService.pendingExercisesCount > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(hevyImportService.pendingExercisesCount) new workout\(hevyImportService.pendingExercisesCount == 1 ? "" : "s") available")
                                .font(.montserratMedium(size: 14))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        }

                        Spacer()

                        Button("Import All") {
                            importWorkouts()
                        }
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(hevyColor)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green.opacity(0.7))
                        Text("All workouts synced")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                        Spacer()

                        Button("Check for new") {
                            checkForWorkouts()
                        }
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(hevyColor.opacity(0.8))
                    }
                }
            }

            // Retry button when there's an error
            if hevyManager.isConnected && hevyImportService.lastError != nil {
                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                Button("Retry") {
                    checkForWorkouts()
                }
                .font(.montserratMedium(size: 14))
                .foregroundStyle(hevyColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1),
                            lineWidth: 1
                        )
                )
        )
        .sheet(isPresented: $showingApiKeyEntry) {
            HevyApiKeyEntryView(onSuccess: {
                showingApiKeyEntry = false
                checkForWorkouts()
            })
        }
        .confirmationDialog(
            "Disconnect from Hevy?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                hevyManager.disconnect()
                hevyImportService.lastError = nil
                importedCount = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Hevy connection will be removed. Previously imported workouts will remain.")
        }
        .onAppear {
            if hevyManager.isConnected {
                checkForWorkouts()
            }
        }
    }

    // MARK: - Actions

    private func checkForWorkouts() {
        hevyImportService.lastError = nil
        importedCount = nil
        Task {
            await hevyImportService.checkForNewExercises()
        }
    }

    private func importWorkouts() {
        Task {
            let count = await hevyImportService.importAllExercises()
            if count > 0 {
                importedCount = count
            }
        }
    }
}

#Preview("Disconnected - Light") {
    HevyIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.light)
}

#Preview("Disconnected - Dark") {
    HevyIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.dark)
}
