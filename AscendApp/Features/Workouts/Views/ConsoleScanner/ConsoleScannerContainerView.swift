//
//  ConsoleScannerContainerView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI

/// Main container that orchestrates the console scanning flow
struct ConsoleScannerContainerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared

    @State private var viewModel = ConsoleScanViewModel()

    let onScanConfirmed: (ConsoleScanResult) -> Void
    let onCancel: () -> Void

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                header

                // Content based on state
                Group {
                    switch viewModel.state {
                    case .selectingSource:
                        ConsoleImageSourceView(viewModel: viewModel)

                    case .cropping(let image):
                        ConsoleCropView(
                            image: image,
                            viewModel: viewModel
                        )

                    case .confirmation(let result, let image):
                        ScanConfirmationView(
                            result: result,
                            image: image,
                            onConfirm: { confirmedResult in
                                onScanConfirmed(confirmedResult)
                            },
                            onRescan: {
                                viewModel.rescan()
                            }
                        )

                    case .error(let message):
                        errorView(message: message)
                    }
                }
            }
            .themedBackground()
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    // On crop view, go back to camera; otherwise dismiss
                    if case .cropping = viewModel.state {
                        viewModel.rescan()
                    } else {
                        onCancel()
                    }
                }
                .font(.montserratRegular)
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .opacity(viewModel.isProcessing ? 0.3 : 1.0)
                .disabled(viewModel.isProcessing)

                Spacer()

                Text(headerTitle)
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                // Placeholder to balance the header
                Text("Cancel")
                    .font(.montserratRegular)
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(effectiveColorScheme == .dark ? .black : .white)

            Divider()
                .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
        }
        .background(effectiveColorScheme == .dark ? .black : .white)
    }

    private var headerTitle: String {
        switch viewModel.state {
        case .selectingSource:
            return "Scan Console"
        case .cropping:
            return "Adjust Crop"
        case .confirmation:
            return "Review Results"
        case .error:
            return "Error"
        }
    }

    private func errorView(message: String) -> some View {
        let isRateLimitError = message.lowercased().contains("limit")

        return VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(isRateLimitError ? "Limit Reached" : "Unable to Scan")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(message)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                // Don't show Try Again for rate limit errors
                if !isRateLimitError {
                    Button {
                        viewModel.rescan()
                    } label: {
                        Text("Try Again")
                            .font(.montserratSemiBold(size: 16))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Button {
                    onCancel()
                } label: {
                    Text(isRateLimitError ? "OK" : "Cancel")
                        .font(.montserratSemiBold(size: 16))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isRateLimitError ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)))
                        .foregroundStyle(isRateLimitError ? .white : (effectiveColorScheme == .dark ? .white : .black))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}
