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
                            onCrop: { croppedImage in
                                Task {
                                    await viewModel.processCroppedImage(croppedImage)
                                }
                            },
                            onCancel: {
                                viewModel.rescan()
                            }
                        )

                    case .processing:
                        processingView

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
                    onCancel()
                }
                .font(.montserratRegular)
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

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
            return "Crop Image"
        case .processing:
            return "Processing"
        case .confirmation:
            return "Review Results"
        case .error:
            return "Error"
        }
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .accent))

            Text("Analyzing console image...")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text("This may take a few seconds")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

            Spacer()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Unable to Scan")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(message)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
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

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.montserratSemiBold(size: 16))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}
