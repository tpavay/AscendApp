//
//  DebugToolsView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

#if DEBUG
struct DebugToolsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = DebugToolsViewModel()
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

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

            // Actions
            VStack(spacing: 12) {
                ForEach(section.actions) { action in
                    DebugActionRow(
                        action: action,
                        isExecuting: viewModel.isExecuting(action),  // Check if THIS specific action is executing
                        onExecute: {
                            Task {
                                await viewModel.executeAction(action)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
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
}
#endif
