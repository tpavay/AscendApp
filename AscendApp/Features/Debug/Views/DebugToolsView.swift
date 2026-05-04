//
//  DebugToolsView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI
import SwiftData

#if DEBUG
struct DebugToolsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DebugToolsViewModel()
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Navigation sections
                inspectionSection
                
                // Debug sections
                ForEach(viewModel.sections) { section in
                    debugSection(section)
                }

                // Warning footer
                warningSection
            }
            .padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Debug Tools")
        .navigationBarTitleDisplayMode(.large)
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = viewModel.successMessage {
                Text(message)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .onChange(of: viewModel.successMessage) { _, newValue in
            showSuccessAlert = newValue != nil
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
    }

    // MARK: - Inspection Section
    
    private var inspectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Inspection")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text("View and manage app data")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            .padding(.horizontal, 20)

            // Navigation Links
            VStack(spacing: 12) {
                NavigationLink {
                    PersonalRecordsDebugView()
                } label: {
                    inspectionRow(
                        title: "Personal Records",
                        description: "View all current and historical PRs",
                        icon: "trophy.fill",
                        iconColor: .orange
                    )
                }
                .buttonStyle(.plain)
                
                NavigationLink {
                    HapticsTestView()
                } label: {
                    inspectionRow(
                        title: "Haptics Test",
                        description: "Test all haptic feedback types",
                        icon: "waveform",
                        iconColor: .purple
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TelemetryConsoleView()
                } label: {
                    inspectionRow(
                        title: "Telemetry Console",
                        description: "Inspect recent analytics events, screen views, and breadcrumbs",
                        icon: "waveform.path.ecg.rectangle",
                        iconColor: .mint
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func inspectionRow(
        title: String,
        description: String,
        icon: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 50))
                .foregroundStyle(.accent)

            Text("Developer Tools")
                .font(.montserratBold(size: 24))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("These tools are only available in debug builds")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Debug Section

    private func debugSection(_ section: DebugSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }
            .padding(.horizontal, 20)

            if section.title == "Workouts" {
                workoutPresetPicker
                    .padding(.horizontal, 20)
            }

            // Actions
            VStack(spacing: 12) {
                ForEach(section.actions) { action in
                    DebugActionRow(
                        action: action,
                        isExecuting: viewModel.isExecuting(action),  // Check if THIS specific action is executing
                        onExecute: {
                            Task {
                                await viewModel.executeAction(action, modelContext: modelContext)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var workoutPresetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preset")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))

            Picker("Workout Preset", selection: $viewModel.selectedWorkoutPreset) {
                ForEach(WorkoutSeedPreset.allCases) { preset in
                    Text(preset.pickerLabel)
                        .tag(preset)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)

                Text("Debug Mode Only")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer()
            }

            Text("These tools will not be included in release builds. They are only available during development.")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

#Preview {
    NavigationStack {
        DebugToolsView()
    }
    .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}
#endif
